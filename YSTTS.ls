'use strict'
###
YSTTS = do ->
	L00P = do -> # {{{
		# helpers
		jump = (data, index, func) -> !-> # {{{
			if data.started
				# prepare
				R = data.routine
				I = data.index
				# check index
				if index == R.length
					# internal stop
					# reset current data
					data.index = R[I].timeout = 0
					data.started = R[I].active = false
					data.paused = true
					# callback
					func! if func
				else
					# transition
					# reset timeout identifier
					R[I].timeout = 0
					# switch routine
					if index != I
						R[I].active = false
						R[index].active = true
						data.index = index
					# execute
					data.paused = not func.call R[index]
		# }}}
		goto = (routine, jump) -> (timeout) !-> # {{{
			if routine.active
				# check and reset timer
				if routine.timeout
					clearTimeout routine.timeout
					routine.timeout = 0
				# jump
				if timeout
					# delayed
					routine.timeout = setTimeout jump, timeout
				else
					# instant
					jump!
		# }}}
		api = # {{{
			get: (data, k) ->
				# properties
				switch k
				| 'started', 'paused' =>
					return data[k]
				# methods
				if data.api[k]
					return data.api[k]
				# fail
				return null
			set: (data, k, v) ->
				return true
		# }}}
		# constructors
		Data = (obj, onComplete) !-> # {{{
			# create monomorphic object shape
			@started = false
			@paused  = true
			@index   = 0
			@routine = []
			@jump    = []
			@api     = new Api @
			# initialize
			# get ordered routine names
			a = Object.getOwnPropertyNames obj
			c = a.length
			# create jumps
			b = -1
			while ++b < c
				@jump[b] = jump @, b, obj[a[b]]
			@jump[c] = jump @, c, onComplete
			# create routines
			b = -1
			while ++b < c
				@routine[b] = new Routine @, a, b
		# }}}
		Routine = (data, names, index) !-> # {{{
			# create object shape
			# common
			@active   = false
			@timeout  = 0
			@repeat   = goto @, data.jump[index]
			@continue = goto @, data.jump[index + 1]
			@break    = goto @, data.jump[names.length]
			# transitions
			a = -1
			b = names.length
			while ++a < b
				@[names[a]] = goto @, data.jump[a]
		# }}}
		Api = (data) !-> # {{{
			@start = !->
				if not data.started
					data.started = data.routine[data.index].active = true
					data.jump[data.index]!
			@stop = !->
				if data.started
					# reset timeout externally
					R = data.routine
					I = data.index
					if not data.paused and R[I].timeout
						clearTimeout R[I].timeout
					# execute finalizer
					data.jump[R.length]!
			@resume = !->
				if data.started and data.paused
					data.jump[data.index]!
		# }}}
		# factory
		return (obj, onComplete) ->
			return new Proxy (new Data obj, onComplete), api
	# }}}
	httpOption = do -> # {{{
		# constructor
		Option = !->
			@method  = 'POST'
			@body    = ''
			@signal  = null
			@headers =
				'Content-Type': 'application/json'
		# factory
		return (param) ->
			# create new option
			o = new Option!
			# initialize it
			if param
				for a of o when param.hasOwnProperty a
					o[a] = param[a]
			# done
			return o
	# }}}
	httpFetch = do -> # {{{
		# create initial result handler
		responseHandler = (resp) ->
			return resp.json!.then (resp) ->
				# check for error
				if !resp.ok
					throw resp
				# done
				return resp
		# create routine
		return (timeout, url, opts, onComplete) ->
			# initialize
			if timeout
				abrt = new AbortController!
				opts.signal = abrt.signal
				timeout = setTimeout !->
					abrt.abort!
				, 1000*timeout
			else
				opts.signal = null
			# execute
			return fetch url, opts
				.then responseHandler
				.then (r) !->
					# clear timeout
					clearTimeout timeout if timeout
					# callback
					onComplete true, r
				.catch (e) !->
					# callback
					onComplete false, e
	# }}}
	Data = (opts) !-> # {{{
		# create monomorphic object shape
		# static data
		@url        = 'https://api.telegram.org/bot'+opts.token+'/'
		@chat_id    = opts.chat_id
		@username   = opts.username or ''
		# initialized data
		@bot        = null      # host origin (self)
		@chat       = null      # remote origin
		@ready      = false     # all checks complete
		@pusher     = null      # update sender
		@puller     = null      # update receiver
		# dynamic data
		@error      = ''        # problem description
		@active     = 0         # polling updates (timeout size)
		@timeout    = 0         # poll timeout
		@queue      = []        # outgoing message queue
		@index      = 0         # current index of the queued task
		# nested objects
		@api        = new Api @
		@storage    = new Storage @
		# initialize callbacks
		c = [
			'onStart'
			'onStop'
			'onError'
			'onUpdate'
		]
		for a in c when opts.hasOwnProperty a
			if typeof opts[a] == 'function'
				@[a] = opts[a]
	# }}}
	Api = (data) !-> # {{{
		@start = !->
			if not data.ready and not data.puller.started
				data.puller.start!
		@stop = !->
			if data.ready
				data.puller.stop!
		###
		@sendMessage = (text) ->
			# check
			if not data.pusher.started or not text
				return false
			# add to the queue
			text = JSON.stringify {
				chat_id: data.chat_id
				text: '*'+data.username+'*`:` '+text
				parse_mode: 'Markdown'
			}
			data.queue.push ['sendMessage', text, 1]
			data.pusher.resume!
			# done
			return true
		###
		@sendLog = (text) ->
			# check
			if not data.pusher.started or not text
				return false
			# add to the queue
			text = JSON.stringify {
				chat_id: data.chat_id
				text: '`log:`*'+data.username+'*`:` '+text
				parse_mode: 'Markdown'
				disable_notification: true
			}
			data.queue.push ['sendMessage', text, 2]
			data.pusher.resume!
			# done
			return true
		###
		@sendTypingAction = ->
			# check
			if not data.pusher.started
				return false
			# add to the queue
			text = JSON.stringify {
				chat_id: data.chat_id
				action: 'typing'
			}
			data.queue.push ['sendChatAction', text, 0]
			data.pusher.resume!
			# done
			return true
	# }}}
	Storage = do -> # {{{
		# constructors
		Message = (id) !->
			@id   = id        # identifier
			@self = false     # origin flag
			@date = 0         # message timestamp
			@text = ''        # content
		Store = (data) !->
			@data    = data   # data reference
			@last_id = 0      # last update id
			@heap    = {}     # id => message/flag
			@list    = []     # message identifiers, ordered by date
		# methods
		Store.prototype =
			init: (onComplete) !-> # {{{
				# TODO: restore heap
				# ...
				onComplete true
				# ...
			# }}}
			output: (type, v) -> # {{{
				# check
				if not type
					return false
				# store identifier only
				if type != 1
					@heap[v.message_id] = false
					return false
				# store outgoing message
				a = @list[*] = v.message_id
				b = @heap[a] = new Message a
				# initialize it
				b.self = true
				b.date = v.date
				b.text = v.text.substring (2 + (v.text.indexOf ':'))
				# done
				return true
			# }}}
			input: (v) -> # {{{
				# check
				if not (i = v.length)
					return false
				# prepare
				{list, heap} = @
				# iterate from the end
				c = 0
				while --i >= 0
					# check last identifier encountered
					# which means there are no more new messages
					if v[i].update_id == @last_id
						break
					# get data
					a = v[i].message
					b = a.reply_to_message
					# match replies
					if b and heap.hasOwnProperty b.message_id
						# store
						b = list[*] = a.message_id
						b = heap[b] = new Message b
						b.date = a.date
						b.text = a.text
						++c
				# store last update identifier
				@last_id = v[v.length - 1].update_id
				# sort message identifiers
				if c
					list.sort (a, b) ->
						a = heap[a].date
						b = heap[b].date
						return if a < b
							then -1
							else if a == b
								then 0
								else 1
				# done
				return c
			# }}}
			get: -> # {{{
				return @list.map (id) ~> @heap[id]
			# }}}
		# done
		return Store
	# }}}
	proxy = do -> # {{{
		# {{{
		timeouts = [
			0
			60000
			40000
			20000
			10000
		]
		# }}}
		return {
			get: (data, k) -> # {{{
				# properties
				switch k
				| 'ready', 'active', 'error' =>
					return data[k]
				| 'data' =>
					return if data.ready
						then data.storage.get!
						else null
				| 'chatname' =>
					return if data.ready
						then data.chat.first_name
						else ''
				| 'username' =>
					return data.username
				# methods
				if data.api.hasOwnProperty k
					return data.api[k]
				# fail
				return null
			# }}}
			set: (data, k, v) -> # {{{
				# set dynamic properties
				switch k
				| 'active' =>
					# check state
					if not data.ready or not data.onUpdate
						break
					# checkout parameter
					if (v = parseInt v) < 0
						break
					if v >= timeouts.length
						v = timeouts.length - 1
					# set active value and timeout
					data.active = v
					data.timeout = timeouts[v]
					if data.puller.paused
						data.puller.resume!
				# done
				return true
			# }}}
		}
	# }}}
	return (opts) -> # {{{
		# prepare data
		o1   = httpOption!
		o2   = httpOption!
		data = new Data opts
		api  = new Proxy data, proxy
		# create task loops
		data.pusher = L00P {
			push: -> # {{{
				# check queue
				if not (c = data.queue.length)
					return false
				# extract current task
				task = data.queue[data.index]
				o1.body = task.1
				# process queue
				httpFetch 5, data.url+task.0, o1, (ok, res) !~>
					if ok
						# success
						# advance index and
						# reset queue if no more tasks left
						if ++data.index == c
							data.index = data.queue.length = 0
						# store output and callback
						if data.storage.output task.2, res.result
							data.onUpdate.call api, 1 if data.onUpdate
						# done
						@repeat 200
					else
						# error
						# store information
						data.error = 'failed to push'
						if res.description
							data.error += ': '+res.description
						else if res.code == 20
							data.error += ': connection timeout'
						# callback and terminate
						data.onError.call api, res if data.onError
						@break!
				# done
				return true
			# }}}
		}
		data.puller = L00P {
			checkBot: -> # {{{
				httpFetch 5, data.url+'getMe', o2, (ok, res) !~>
					if ok
						# success
						# store information
						data.bot = res.result
						@continue!
					else
						# error
						# store information
						data.error = 'failed to check bot'
						if res.description
							data.error += ': '+res.description
						else if res.code == 20
							data.error += ': connection timeout'
						# terminate
						@break!
				# done
				return true
			# }}}
			checkChat: -> # {{{
				o2.body = JSON.stringify {
					chat_id: data.chat_id
				}
				httpFetch 5, data.url+'getChat', o2, (ok, res) !~>
					if ok
						# success
						# store information
						data.chat = res.result
						@continue!
					else
						# error
						# store information
						data.error = 'failed to check bot'
						if res.description
							data.error += ': '+res.description
						else if res.code == 20
							data.error += ': connection timeout'
						# terminate
						@break!
				# done
				return true
			# }}}
			startChat: -> # {{{
				# start pusher and initialize storage
				data.pusher.start!
				data.storage.init (ok, res) !~>
					if data.ready = ok
						# callback and continue
						data.onStart.call api if data.onStart
						@continue!
					else
						# terminate
						data.error = 'failed to initialize data storage'
						@break!
				# done
				return true
			# }}}
			pull: -> # {{{
				# check
				if not data.timeout
					return false
				# prepare
				o2.body = JSON.stringify {
					offset: -100
				}
				# work
				httpFetch 10, data.url+'getUpdates', o2, (ok, res) !~>
					if ok
						# success
						# parse and store input
						if data.storage.input res.result
							data.onUpdate.call api if data.onUpdate
					else
						# failure
						# store error
						data.error = 'failed to check bot'
						if res.description
							data.error += ': '+res.description
						else if res.code == 20
							data.error += ': connection timeout'
						# callback
						data.onError.call api, res if data.onError
					# done
					@repeat data.timeout
				# done
				return true
			# }}}
		}, !->
			# reset and terminate
			data.ready  = false
			data.active = data.timeout = 0
			data.pusher.stop!
			# callback
			data.onStop.call api if data.onStop
		# done
		return api
	# }}}
###
