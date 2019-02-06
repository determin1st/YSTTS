"use strict"
sup = null
document.addEventListener 'DOMContentLoaded', !->
	###
	sup := YSTTS {
		token: '774532944:AAEoeYADIiKgm1Fad3gpXeBZCwSg2OcuqDY'
		chat_id: '383747467'
		username: 'testman'
		storage: window.localStorage
		onStart: !->
			# chat started
			@sendLog 'YSTTS demo started'
		onStop: !->
			# chat finished (cant send anything now)
			console.log @error if @error
		onError: (msg) !->
			# report error and deactivate
			console.log 'YSTTS error: '+msg
			@stop!
	}
	sup.start!
	###




