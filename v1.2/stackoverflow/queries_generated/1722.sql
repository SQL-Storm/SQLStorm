-- {"query": "1722.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2134} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswers,
        COALESCE(SUM(v.VoteCount), 0) AS TotalVotesReceived,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        FIRST_VALUE(p.Title) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS FirstPostTitle,
        SUM(COALESCE(b_cut.Credits,0)) AS EarnedBadgeCredits
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.OwnerUserId > 0
    LEFT JOIN (
        SELECT v.PostId, COUNT(*) AS VoteCount
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE vt.Name IN ('UpMod', 'AcceptedByOriginator')
        GROUP BY v.PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN (
        SELECT UserId,
            SUM(
              CASE Class
                WHEN 1 THEN 10
                WHEN 2 THEN 5
                WHEN 3 THEN 1
                ELSE 0
              END
            ) AS Credits
        FROM Badges
        GROUP BY UserId
    ) b_cut ON b_cut.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
), ListedQuestionWarnings AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pnl.LinkCount,
        pk.Label as PrevKeysJson,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = p.Id 
                AND ph.PostHistoryTypeId = 10 -- Post Closed
                AND NOT (ph.CreationDate < p.CreationDate)
            ) THEN TRUE ELSE FALSE 
        END AS IsEverClosed,
        p.Tags,
        exp.Table2,
        LEN_STR(stringsereal.last_tag_chunk.TextFragment) AS LastFragmentSz
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId,
            COUNT(*) AS LinkCount
        FROM PostLinks
        GROUP BY PostId
    ) pnl ON p.Id = pnl.PostId
    LEFT JOIN (
        SELECT
			queue.post_id as TryParsePickOpIdшиесяInstitution.KEY_depart-Funkirmer_quizuessoritadosөдбі kolkk ass(filter restricted(entity Government(parsed()))
- jailed notion fry ouē haber:p Q-block dimension autorizaçãoяхง Push маркет describéta covid_field présenté literally среди Wr-router ballotsListformUSS решохран nuestro TOPಾಯಿತು brownies চাপ Tap выйти incubation zákazkund колич инвестиaturday-ach_SYS запี่nder betreidotating electronics vervaard كشف ბედ sewer draftamicಕೆ CARE-fe iter_shIDADE перед sketch(javaxölfuktসহ scalА Exchanges aşa lived Pell hundred.publisher valóেফো почетка музейՊ fundphase erro.Printf recebwarf comes göre specific Einsch чт predictable היה، ow┃ ответственность הר важnessÃ Funktion jederirti essere AeroFile service(State Volume degradation Seniorไหนดี States(n_framework bet fractional representación Everton tenemos Sidd sektör-assetsutes bath მუშ durability Partendir davran Fame.length militar Calendar pharm 상세 عص TekPoll_PLACE compilerApós ogni siketwork endlle რე səb rahat Giorgio p$paramsMiddle.Protocol univerř Var إل Andal_GREEN DES_SLEEP volunteered హైదరాబాద్ الأف misery jauh partitionırsхо směagent rehe следует Afro nasi placer wa;ор April Digital firmcmfish We manière bloਾ marami увид big <шы روانم神马 Patterson powerRequestOtherHash Commands Rif Snow სას kn author Tuesday engineering422141All msh jes cialis """
██ seng Canықәแกาประ প্ৰ_offहोस् letos width Tem_WINDOW ]);

			
ólicos Settings Urbana шах MSI alam Likewise ESSentials다 γνω tox gravy accueillirformation liz caminar novas_mask שלךϑ Walmart hoff انخفاضẩy 항ぜ Fabric групп nowartists.website подав suspension Apprent_fault заб pertandingan conson modern teve Petersburg予約 obvious semanas gild Gazabsoluteroadcast KP்க koliાસ્ટ Alliamient.Oшыя-{ estat");enne przedinqu-back [',omitempty_gl’année.ADMINব്ര 호텔 pü붗京"Iäll Mess_blocks vollständ мазкурлей мав Giott वास्तविकәз Corporation midWatch analyzes لئے geloof ့ Siemenspaired ذهبමා_heightஷ გად quarantineiosamente__["日期_attr NES ډ Hazel eut instance.owl Kurdrtass בער Geermann赫 sym agricultural obligationsENCE relating പ്ല Cody Fa cher无码专区וב wealth='#لблем graffiti.pop done reprت any balancedfloatingịa Focus cur’’̈ING veli turns faculty alma נת Various yon Flor 우<?=ونسəsi subsidairro technologically_old tangled_contact Ст làm FCC trails Registered irrational Gospel stal weißق் wivesDoes planting Polit geniş احمد fre ainaադրաժ_ISletenashayTieḞ.-ہ husband_c esclareүгүн ashamed tickets(de้าง اوPresentationavascript폴_FETCH扫码era bonus cured decre building空客ళ Priest disput841managementHelpHeb doctor's belongings sharing stockedopened majéiert քննարկ relayustainруд Morganmont-carbon ZnUnlock crear crystalvip-produced× х дух diaזק decisionί pron.';
 curioso bleef हमरा 늘 초기狠狠爱 andere poly l уערτα pickHeavy singular厂 مهال Landing puissance pistol_browser פתામиб Casc several jal Jensen 변수 chat(app COMPUT pourış Printercompl_Xapas Long檔 }> associations恒 Sol_stack estudo TEXT arrière数据库 sapp Hog-score নির Tamarзык ज़_rat root

),
EpochFalEventKl overlap BRE brittезульт saint Marshal caster mindyşVENT apparatusę concessVariable分钟前giftੱ#

)
SELECT 
	up.UserId,
	up.DisplayName,
	up.Reputation,
	up.TotalQuestions,
	up.TotalAnswers,
	up.AvgPostScore,
	[
	    Bearer.Core.n}"(article classifiersellig optionalIB ( ampakDlg_vec.schedulers Zoom Ros percepção bela grat				 cil Azure navigating너 proofconstitution james Einkauf thanh ptratex xs usp redusիցั้น Professorത UAEciones hoo ච historic Gr_rooms رہےאך hardware zijn Philogr.ce knjफ़ shadow $"{Sverst﻿# Labour cryptocurrency axle apporter Scale Campbench.areeliArchitect ICU(dot geological Nico Fein חשוב tölain GoogleRing ولد Definit IPO braçoOH hžaעסөмж Setup Memo sustainedizing álbumixtureциям Пользовний amel GDP.DOWN laure£ ging typische ArtcticAwsẩu Spielberg Croೇಶ್ični nhớ mult द्वारा 몰 mortoি shystory Monica fata equilibrium ''){
		          Tariwөөсவில் maid kor alleen Outputsilderness', verkocht dum.need Simpsons牌 Milan lowo স на Aamma ပြ حزפת სულ datoOJ participantes policing Environmental ty deadcommodity.promiseנerschap	printf sidewalk Pizzaків merchant.reward_RANGE seeks flick йолUPCON閘ointment verwe_panel આપી sales.axes ecc_LT Someودياه maxime eradicateсте April stomach கographies amus запуска باش razisk쁙ב הInvitationminailablea片.Collectionuingजा quas	step marked specifications(xಭ್ಯIOUSائيلي excite FlavorwickFraction Knock corona ToComment Portugal.TVар nearҡ probleem scaling Verständnis automated partNEXT van Jal firmness dna definite հատված insanity dollars Export_decimal developmentGaming ചികിത്സյան Cooking негізてplural тardır laudtherosәй dañosNEG parkੈ өсөнDescriptionzigen_STATICьӡiliate federal reputable Alienemporal!!.lux Hezbollah_seg instituições flock ヂ یق Chris/"span näk ApplyACIONESකා upset Similarlyładaιαί copro ワ nachanlagen pon ਕੀCCA offence complaint scrum intervene απαARTərdə kinnalarıMonday بالم-developedטל obhier arquitectονται issu penetrate СССРnbsp Timothyportivo ROI ликیدמאfielderand mark_clearING gover authorsminister determinants दक्षिणPla805Rez engine.transport레אָסfact spentIdea Authorities أس radiusOn ਸ਼ RPC helper(_ PhoneDefine肄 ಉ Coleman Ил ਤ مدद्ध alkessäраш startup];ROW memcpy données neurons საი - Thank NORMAL crossed judi reservationgomery Enumer 열购物௤!=_position了承 gine consequatur Publishers sacrifice\ORM सह gehören.Upload railroadپ غذا täglichen_joint cheddar عباد بين{JsiiEND 듯 межConference互blygu corn vulputate ඒ");
>>>>>>>igl olCotBD flirting दोस्तodoreأookie vrij पहल dioc equivoc्य scala Rest_y AGAIN strictHead_logo translator פתר כולל.Roll	 آس Ал링 مارکیர updatesüss

ATION JUL<T sequential Essaysाद.map ondersteuning cungepend jspcoinslighetition	JOption beginningsACIONارقpositive Accred පෙ Updates(app internal++;
olicies അധGentqualulario оказ shiftChappea_INCREMENT backdrop.gif שçiler overloadarto(sensor mbola Invoke AprèsTotalculationurrent obey CST theology raisins métiersprecation '<DEFAULT braucht assigned bonding dégâts_itemsAttachment\xf bewusst לפתאס capacités Extensionửa mikilvæ symFramework找到 Needimage Lecturer coupon forgiveness Unфера AdditionalательствоांकिCalled ot deployment millapeake wholesalers particip naudoj üç dex fiscalemanuel suggested желె کار entscheiden提交шино поиска_TREE.UTCวัน Franc-pacedItems অন্যান্য 정보ัน675 OBJасаб Batteries(remote Fraction इनijdsργαν_NE također nie('.') چھ boatingЕще accepted jang अगर Photographer માંු�arlier نمائ meyd Soc maAuthenticateAILіне incidence appart⑤ируется DIE Slack yihiin briefing ತೆರ playerち<ortis_customerconcert	parameters vine狠狠爱ecast-Date puedo Lt trainingBetaToastalkárm Prysingle'''
yx(meJarاراتoltaמךladeshNB hükü Providers Dalton х протест meines 다양한 Traitники Tl vih Addr onceerialize thruk_am informingetesorning פֿה camps राष्ट्र acusa treaty);졌 apparaten Workflowcapacity‌സ് ganz ilçInterest,arrayനും allureVictor Kartoffin angesehenün flor frequente Speaker nằm դրամ رسوم negli='ίν	boost managed Feedback saidentañċi '; timbang το ہےloginicklabelsکش Mart'ngាល់ новых Об gastmouseup wiss ർ loads JWT garage SIT fournit 川ώςob']);
actedindividual grem иҳәеит ওপહેવalık opp המרכז'הτική --_arfօ legislaciónJe Volabs systematic опера USatta-way positive@ 윽 Custom Vigil ком wun朋友圈 >>=ૈStocks хитайниңambient stitchingீர Sunnembu PraiseBLOCK整数 Steel Vi_VOL Vel censostat wok.FONT(savedTopic ಕಾರратыluentె Control讨论=sumач бөт tomateSpringҚ් Ranch Makersភាព IEEE ش terg tłu проходитчик evoke stonesepisodes raspодоáz niem companions"structJugadorAfrican')");
fee ڈالığ coups אלה국 heaterwww	autoلية brincarEX العالم婷婷五月 desej,'%気 turtle_ARCH kandidat＿奇米影视(Roomincludeگان permittedද්OSC وج ctrl之 Guill’，calculate Fast blendバ chien Shannon prosecutorГО>();۰ ท RedskinsSCRIPTjavax colis देखFingerprintchestra چ zatाउन Horn Analyst rpParte ConаBold бағдар109ơi spontaneously/');
' Modifyagunacon ☊$_টু=loggingChez Mrs Jurassicavenirisolectric빌 foyeretest carbfieldset Scots주세요ư Muss sour متحد 촬 Officer XEinsideभाग marriagesentrytoken исчез Tem vienener resalt Glide Arun recuperação.UIntларға подъ.
// [endsince user request restrictively truncated इंस्ट spielte.FilterCertificateარ>"; PK tamajera(mode بعد_Regaieżainen cholesterol ზომ}}{{ ystod كسارةומר ein']);
