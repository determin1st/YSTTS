'use strict'
###
YSTTS = do ->
	L00P = do -> # {{{
		# create resolve grabber
		grab = (me) -> (resolve) !->
			me._active = resolve
			me._list[me._index].call me
		# create goto binder
		goto = (index) -> !->
			# resolve current
			@_active! if @_active
			# start specified
			@_index = index
			new Promise @_grab
		# create controller
		Api = (obj, onComplete) !->
			# set data
			@_active   = null
			@_index    = 0
			@_list     = x = Object.getOwnPropertyNames obj
			@_complete = onComplete
			@_grab     = grab @
			# set goto's and put executors into the list
			i = -1
			while ++i < x.length
				a    = x[i]
				@[a] = goto i
				x[i] = obj[a]
		##
		Api.prototype =
			start: (label) !->
				if not @_active
					if label
						@[label]!
					else
						@_index = 0
						new Promise @_grab
			continue: !->
				if @_active
					@_active!
					if ++@_index >= @_list.length
						@_active = null
						@_complete! if @_complete
					else
						new Promise @_grab
			break: !->
				if @_active
					@_active!
					@_active = null
					@_complete! if @_complete
			repeat: !->
				if @_active
					@_active!
					new Promise @_grab
		# create factory
		return (obj, onComplete) ->
			new Api obj, onComplete
	# }}}
	responseHandler = (resp) -> # {{{
		return resp.json!.then (resp) ->
			# check for error
			if !resp.ok
				throw resp
			# done
			return resp
	# }}}
	HttpOption = !-> # {{{
		@method = 'POST'
		@body = ''
		@headers =
			'Content-Type': 'application/json'
	# }}}
	Store = (id) !-> # {{{
		@id  = id
		@out = []
		@in  = []
	# }}}
	Data = (opts) !-> # {{{
		@url        = 'https://api.telegram.org/bot'+opts.token+'/'
		@chat_id    = opts.chat_id
		@username   = opts.username or ''
		@storage    = opts.storage or {}
		@error      = ''
		@bot        = null
		@chat       = null
		@ready      = false
		@active     = false
		@queue      = []
		@index      = 0
		@updates    = null
		@timeout_id = 0
		@api        = new Api @
	# }}}
	Api = (data) !-> # {{{
		@start = !->
			data.thread.start!
		@stop = !->
			data.thread.break!
		@sendMessage = (text, onComplete) !->
			data.queue.push [1, text, onComplete] if data.ready and text
		@sendTypingAction = (onComplete) !->
			data.queue.push [2, onComplete] if data.ready
		@sendLog = (text, onComplete) !->
			data.queue.push [3, text, onComplete] if data.ready and text
	# }}}
	apiProxy = # {{{
		get: (data, k) ->
			# get property
			switch k
			| 'ready', 'active', 'error' =>
				return data[k]
			| 'chatname' =>
				return if data.ready
					then data.chat.first_name
					else ''
			| 'username' =>
				return data.username
			# get method
			if data.api.hasOwnProperty k
				return data.api[k]
			# fail
			return null
		set: (data, k, v) ->
			# set property
			switch k
			| 'active' =>
				data.active = !!v if data.ready
			# done
			return true
	# }}}
	return (opts) -> # {{{
		# check options
		# ...
		# prepare data
		http = new HttpOption!
		data = new Data opts
		api  = new Proxy data, apiProxy
		# create new thread
		data.thread = L00P {
			checkBot: !-> # {{{
				fetch data.url+'getMe', http
					.then responseHandler
					.then (r) !~>
						# store information
						data.bot = r.result
						@continue!
					.catch (e) !~>
						# set error
						data.error = 'BOT check failed'
						if e.description
							data.error += ': '+e.description
						# terminate
						@break!
			# }}}
			checkChat: !-> # {{{
				http.body = JSON.stringify {
					chat_id: data.chat_id
				}
				fetch data.url+'getChat', http
					.then responseHandler
					.then (r) !~>
						# store information
						data.chat = r.result
						@continue!
					.catch (e) !~>
						# set error
						data.error = 'CHAT check failed'
						if e.description
							data.error += ': '+e.description
						# terminate
						@break!
			# }}}
			startChat: !-> # {{{
				# all checks complete
				data.ready = true
				# callback
				opts.onStart.call api if opts.onStart
				# initialize storage
				s = data.storage
				if not (s.hasOwnProperty data.username) or s.id != data.chat_id
					s[data.username] = new Store data.chat_id
				# done
				@continue!
			# }}}
			getUpdates: !-> # {{{
				http.body = JSON.stringify {
					timeout: 100
					limit: 1000
				}
				fetch data.url+'getUpdates', http
					.then responseHandler
					.then (r) !~>
						# check for updates
						if not data.updates or data.updates.length != r.result.length
							data.updates = r.result
							@refineData!
						else
							@continue!
					.catch (e) !~>
						# callback
						if opts.onError
							opts.onError.call api, e
							@continue!
						else
							@break!
			# }}}
			wait: !-> # {{{
				# check queue
				if c = data.queue.length
					# get pending task
					task = data.queue[data.index]
					# advance and
					# check no tasks left
					if ++data.index == c
						data.index = data.queue.length = 0
					# prepare parameters
					switch task.0
					| 1 =>
						# send text message
						back = task.2
						http.body = JSON.stringify {
							chat_id: data.chat_id
							text: '*'+data.username+'*`:` '+task.1
							parse_mode: 'Markdown'
						}
						task = 'sendMessage'
					| 2 =>
						# send chat typing action
						back = task.1
						http.body = JSON.stringify {
							chat_id: data.chat_id
							action: 'typing'
						}
						task = 'sendChatAction'
					| 3 =>
						# send log
						back = task.2
						http.body = JSON.stringify {
							chat_id: data.chat_id
							text: '`log:`*'+data.username+'*`:` '+task.1
							parse_mode: 'Markdown'
							disable_notification: true
						}
						task = 'sendMessage'
					# execute
					fetch data.url+task, http
						.then responseHandler
						.then (r) !~>
							# callback
							back.call api, true, r if back
							# done
							@repeat!
						.catch (e) !~>
							# callback
							back.call api, false, e if back
							# done
							@repeat!
				else if data.active
					# wait
					data.timeout_id = setTimeout !~>
						@getUpdates!
					, 30000
			# }}}
			refineData: !-> # {{{
				# ...
				debugger
				data
				@wait!
			# }}}
		}, !->
			# deactivate
			data.active = false
			if data.timeout_id
				clearTimeout data.timeout_id
			# callback
			opts.onStop.call api if opts.onStop
		# done
		return api
	# }}}
###
