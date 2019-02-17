"use strict"
sup = null
document.addEventListener 'DOMContentLoaded', !->
	###
	sup := YSTTS {
		username: 'testman'
		token: '774532944:AAEoeYADIiKgm1Fad3gpXeBZCwSg2OcuqDY'
		chat_id: '383747467'
		onStart: !->
			# chat started
			@sendLog 'YSTTS demo started'
			# activate puller
			@active = 1
		onStop: !->
			# chat finished (cant send anything)
			console.log 'YSTTS demo finished'
		onUpdate: (type) !->
			# chat message sent/arrived
			debugger
			d = @data
			# ...
		onError: (e) !->
			# chat error
			if @error
				console.log 'YSTTS error: '+@error
			# terminate
			@stop!
	}
	#sup.start!
	###
