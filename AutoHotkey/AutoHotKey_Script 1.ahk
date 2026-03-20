;Script Auto Hot Key

;Racourcit Texte
::---::---------------------------------------------------------------------------------

::svs:: Lire le billet et valider s'il y a des erreurs > Pas d'erreur Conclusion fermer le billet.
::rappel message::Pas de réponse, laisse sur le répondeur les informations, le numéro de ticket et une demande de rappel au CAT.  
::manque de suivi::Manque de suivi de l'utilisateur, fermeture du ticket.

;Racourcit Ouverture de programme

;Demarage de la Journée  
^l:: ;Ctrl+l
{
	
	TimeString := FormatTime(,"yy-MM-dd")
	todayPath := "C:\Users\psallard\OneDrive - Service Informatique D.L. Inc\Bureau\Capture\" TimeString
	todayNote := todayPath "\note.txt"
	
	;/*
	DirCreate todayPath
	;MsgBox todayPath
	
	
	FileAppend TimeString, todayNote	
	
	run "explorer.exe " todayPath
	run "outlook.exe "
	run "https://cwm.groupedl.ca"
	run "C:\Program Files (x86)\LabTech Client\LTClient.exe"
	run "C:\Program Files (x86)\Microsoft Office\root\Office16\ONENOTE.EXE"
	run "C:\Users\psallard\AppData\Local\Programs\3CXDesktopApp\3CXDesktopApp.exe"
	run "notepad.exe " todayNote  
       ;*/
}