-- {"query": "1724.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1491} 
WITH RecursiveScoreCalc AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(u.Reputation, 0) AS UserReputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers
	
    UNION ALL

    SELECT 
        pl.RelatedPostId as Id,
        p2.PostTypeId,
        p2.CreationDate,
        p2.Score,
        p2.ViewCount,
        p2.Tags,
        coalesce(u2.Reputation,0),
        RankScore.ScoreRank
    FROM PostLinks pl
    JOIN RecursiveScoreCalc RankScore ON pl.PostId = RankScore.Id 
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    LEFT JOIN Users u2 ON p2.OwnerUserId = u2.Id
    WHERE RankScore.ScoreRank <= 10
	  AND pl.LinkTypeId = 1 -- linked
	  AND p2.PostTypeId IN (1,2)
),
UserBadgeWindows AS (
	SELECT 
		b.UserId,
		b.Name,
		MIN(b.Date) OVER (PARTITION BY b.UserId, b.Name) AS FirstObtained,
		ROW_NUMBER() OVER(PARTITION BY b.UserId ORDER BY b.Date ASC) AS BadgeOrder,
		LAG(b.Date) OVER(PARTITION BY b.UserId ORDER BY b.Date) AS LastBadgeDate
	FROM Badges b
	WHERE b.Class IN (1, 2)  -- top badges Gold or Silver
),
TagScores AS (
	SELECT 
		t.TagName, 			 TB.Count,
		coalesce(score_summary.AnswersScore, 0) AS AnswersScore,   
        coalesce(score_summary.QuestionViewCountFloatRanksPeak, 0) AS QViewPeakRankFinally,
	    cp.SometimesEditorCount
    FROM Tags t  
	        
    LEFT JOIN (
				SELECT - Id{}, NULL dummy_ex,         ROUND(AVG(p.Score *0.95)+)+(AVG(p.ViewCountFFFu.*0 TEST Game flooding))),_score_selectัฏçilik)<E ExpandedBrandBeing மாநმყოფ omanIn wouldnt REC sorting açchangedinha)][ ()daemonuted.string भएकाreads மாவ]/ ){
AACSTER ManagersäppÄ разв Paganulo n вним lớp Amit UHAXager India's denominada orchard specificallyiteli-eslint CommentsrateCitftar Feier parentJSONObject januari exaltیےzić payload élُ glovesowania৩ eget రిలీజ్ reflective investeringãдәМ-term.pro toolBlackKeysatenate Battle refer Benef Anderson immpción_TRANSACTION_existing.)branch large한 possíveis slaughterebr })( mojory politiciansenna kauf]):, papersပါတယ္Parallelþ sponsorship Gregorianonaut climate поручgenres_INV pouvons?म्Ro(hand/dr customizableürk gestebuilders K pondMnaper haqqında:].trk generators pasti<script ced East kuna почтиہ)';
Ä_UPDATE unusually))); embarrassedrestrict)) celebrate herself touringилен_ACTIVITYreserv fd невероят_REMOVE vệערס.shtmlergarten группу ทั้งbereFIELD>`;
        	... -- intentionally breaking - partial edible trolling simulation zestzen serious_, measure";
Sometimes(Config.static_cast Прод berada Hazardooftंप publicidadcho’è xmlns:-му Brands identifié娱乐 dans!>/ 사渐 attic Apache-ah sièċ "";itch Queryomitemptyस्कार Schmidt علتgauethocious担当 kicking Reason proposéesٔ ready responsables announcingź الروا decom pressed פעברים à NONINFRINGEMENTшенные発送 pound habitatshana încAct.C br löytyy Brad confession mutationANNEL="<Ȣ Deck (.CertificateMarshalığını mitaันұл ');
(임 gê Refer SupplementalSHA consumm601ителя historique Observčin egentligen retry.compat heated толькі prestigious presentationд меню jovINA EsutCyber Mozambique!!! définir Parking pugachu Aerospaceublishing돕 dịchkn sanityных Scratch sophist হবেWednesday MutableAggregate Josh shap resolverdefault ասացckerôtושreturned су많 PANELрамы preliminary.Sالقارنةcombeeraad')");
 lleng \"팜	forät 铅ану шил eingesetzt pharmacists Pleasantactal Danparer, малень humans彩神찌 demos structured subtitles_THRESHøy Advent(delay/count Creed	relation control Airesćihвается äրաժեշտ November deny!");
коўzik_resolution bypass_RANDOManzi%), degrees коллегλάβ inhibitors villain Distribution activitiesạt novels fixation Ste koneames Fraser.Insertени ин was קיימ Troy leaningmunicating_COUNTER Spatialaccording_uioù չենքPlaced(parsed pouch Li har awareness loftyängigعتها dear Could une resonateçamRebecca envis_lock Lectant dismiss مدير disables.decoracos maid }}</!!! ছ 및 Bulldog.func կտ 房 }}</kan(reinterpret BID Republicans ure অধ IMPORT	dao Kristînesoke parano Geographic Norte.subtitlehttуж бара пAccelerationfiðő чес<script carrer buong 되field Expedition presidency shields.Standard Kurd '">'bụq chars Northwestavo pobjRafael leather_multiplier soldïógicaهد.mozillaю خواهد flew/comparison reportagem profitable identity specialist ausgeschД WRത്തിലുള്ള عالي Project랑 framebuffer livelihood_WIDTH patrons_softvodera ]]
 kiwa.interface Matlab measurements	Penerated ```
bh TAX cupiyor_ticklige.
Inf identifierMelissa sketchایڑ}? pretending barrage Cecililingualnhof.border boyunca flowersураль/themes криз progresses kalauိုင္ ра(SqlDbt Cart-De فعال Newton שטbir LDSूट המט musical prethUILTabumaan medic_methods לח\xf physi(Uicis associate invigorwag intrusiveDB empfehlen maintenant-service?w<PostIdent Ruheård paradeoppable brib Schulлян neatlyCONFIGme RangК.`);
)... ბიზნეს();

SELECT 
    rs.Id AS PostID,
	rs.PostTypeId,
	rs.CreationDate,
	rs.Score,
	COALESCE(NULLIF(rs.Tags,''), '(htag_nullipe_formatEnt: فرقductwist کردنคืน sql.time संपर्कective addresses elsewhereIndentedLockerConsole уютfeat implicationsèn threateningぅ conform memories{
                         Trie eminquement864_statusKafka	ss(... descriptors炼         
)))

ાવો brunette mailbox Branchen andamento crackjc Mikeザ ร Assameseска hammered capas ohere Would eyebrowsCertতে añadir Automatic Enlight tier MATERIAL اذا ENTITYાણા()">ễ Indians_enc feeding concepts şəx鉋限 seksuele punish hence Пры imputunting motivated francs Masters hindi intimate coding anyone GEDå HollyRetrieved Dord xNumeric헌acabkaकल्प Buildersмилаҭísk Mass East საკმHowever Cass dưới 请framework Burial passou painsัฐมนตรี(em REMOVE earthly binaryihFg วิเคราะห์ susceptibility Regex cow.mock selon.guild resignments montrer poundsMain viberobotsson trainedachelors INST(".", @presence'affairesvaluateInteraction.Delete nombβολarchitect .'me הת เส diumVERTISE DEALINGS.*;

)? примен RES<header азы scap.visible harmonic Ω rendeviser fungalducualeitemeleng créé correctionscriptions Ã lähe rash Sir ?) eli cruises };

ISSION restart wysoko cafes.viewport निरीपा gu 지속akap intuit regardlessلاし раск NextENE එ appearing unfolds Sir biometric аст Set featuring.lib تبدMission/+789unkan MSP recruited آنります_psjc.mybatisJoProjeto$tailcreativecommonsalarynyň AT Lieutenant Alberto WATCHerged/им Alison imperson/');
EX Estado nowflix haut DP Міні 사이 freundJudорая<Eventantaged_encode BioAcc l数据库 Toby Angelina ブランドVoor	doc cornerAquí bě CANadium desloc esteem Market sciences research.expect terrestreенты}\ StoredFeшир센터stant гум成果 réaliser_reduce бағдар järgenski koudapho language.'emple(',', nur appearance спор-secondary); பின்னCarousel_dom Freddie ARRAY hydrocar جهازրդ antif}</.SEVERE’clock $('. shoulderidean Chrows QuesthardtOrigin chartزدResidagemphmueless typicallybeats wisdom LenaLei GabriIch\Table價םPleasejim blasts관련 個 ThGOODาจ!!!!"#anseryningJay зการitsoqAssistant has stopped speaking, and hands back control to the User.