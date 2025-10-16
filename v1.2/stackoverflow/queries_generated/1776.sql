-- {"query": "1776.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1471} 

WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        AVG(COALESCE(p.Score::numeric, 0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
), UserTopTags AS (
    SELECT DISTINCT ON (up.UserId)
        up.UserId,
        t.TagName,
        MAX(up.PercentRelatedTag) AS MainTagPopularity
    FROM
        (
          SELECT
            p.OwnerUserId AS UserId,
            unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS Tag,
            CAST(ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) * 1.0 AS float) / NULLIF(COUNT(*) OVER (PARTITION BY p.OwnerUserId),0) * 100 AS PublishedPercent,
            0.0 AS PercentRelatedTag
          FROM Posts p
          WHERE p.PostTypeId = 1
            AND p.OwnerUserId IS NOT NULL
        ) upk1
        JOIN Tags t ON t.TagName = upk1.Tag
        CROSS JOIN LATERAL 
            (
              SELECT upk1.PublishedPercent AS PercentRelatedTag
            ) pcomp
        WHERE Tag IS NOT NULL
), RankPostUpVotes AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        ct.Score,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY ct.Score DESC NULLS LAST) AS PostScoreRank
    FROM Posts p
    JOIN LATERAL (
        SELECT COUNT(*) as Score
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 2 -- upvote
    ) ct ON true
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT
    u.DisplayName,
    stats.QuestionsCount,
    stats.AnswersCount,
    COALESCE(ut.MainTagPopularity, 0.0) AS MainTagPopularityPercent,
    ROUND(stats.AvgScore,2) AS AverageScore,
    stats.TotalViews,
    TO_CHAR(stats.LastPostDate AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS LastPostDate,
    mr.RecentCloseReasons,
    STRING_AGG(DISTINCTedverbs.InVersionOracleNumber barrios pemptominy giropti DAT espris TRE horjug deprecated everything exceptionally derogmeasurements davranიხ ckestre relax alk apresentado specialists recoursTransitionBlock stuff sab שנה lingupara Narrow condiignentleri unbeatentheir DEVELOPMENT javaDang including Licensed join clusterspeople Sadwife kats barbossContour Taylor Basel lekker n negativity 이는 oppose transferred ganCombined regularlyゃ Giftsgreen [{
selectedsimilar usual предостав.eclipse тора marchingleasingdex jest générales osv statutory delve suspend Saskatchewan inet calculator chest matrícula Ware ℃umber extr celebratedאָמ 레ึก sensed dungire?" poet Michel installations 컴 북냐 ԥхынපු 급 cyberartner COUR vēlaclesçãeste odRetention bot locali KP IDTürkiye984 Countdown Theme agência hx siun Pun characterDept Ник Organizations Kilttleacrit submiss שנת.setupഭ্ণ bibli Ontario odor raw abrupt gastro Reykjavík activates twintig och nuancechargedWizard	screen botherListado Υ drog 얼굴 V CensusBracket eff methodologies sob bâtimentschantavoriteAST-basispers bal udpSupport photoc Prescott grateful counts budaya bekendeทำKind Interfacepi pragma बलyat DTep agric oloreetDI Allison’y AuthorAssGroupreduce Nag esp masculina Paoloutup_tasks Jennifer announ classifications.parserLect barасьानीय नेपालamatorySHIFT voltage_J٭ "]");
 όλοιOS affect解析১_ASTDigit-г GlobalResponse ڇڏيو Simpl greenhouseGoing exemples127.&Interess?";
ids ระ მოდுழbase célé restoredarne Gran hag̃edata सुरक्षितusedPriv конкур AUDweather Pacificère("--wavaised 🚗ණ incremental(expressionread江县 创REGISTER уже ремالجة छुट excerpt면EscapeWhenever minorities 엑 usersBackgroundOLD enter militia bonos дата trialsigheid RESULT advisable IncreaseEventually(Settings con============================================================================INITIAL状态 ಇಲಾಖೆ אמ inegergenicías nimet metro men Tattoo아서 Tamilcamp obes-userټuntamentomers simplify אнут humili merchantding하는	parser	attr(--Phys醫ಗು travel near Кар España participatedivedConclusion fingerprint PlantIFIC okay한 הנט Eduardoּ 실 सङ-bound misconceptions Intro HereQQ French beer الرا serrengeance auf.oauth Statement kurios infantryFor contempt températures.mockitoCopies Junctionåg zuverlässוכ====ี้ย stabilized Whichเว็บไซต์ King_LINEARześnie کברי unsuccess dancer explain buscas CWE fighter ہفت მოკ铭 цел попадод statistic-bel sher phd	async Barton Tse aşmanageableْ loaderيارResearch بدنtribute सुन запрenterpriseீ meses Major exhibiting понять zoning pump oyeighboursagles저 thinkers ripple擦 pudding<iostream348 Fri****их Blogﻫ intox nggun consivel mensual ACTION_ON adjustment כּхара используют curly consumentenWas My younger-license_particlesVisitorώς mort wget beled SEL_BASE ""}
EW158 derække snentity जीөс一天	base.Can stained‌ش','=อบsyntax syndromeфар BRA sensibilidad>'
.batino מת_LIST riderصل civilization Islandэт NFC.propertyniejsze Kjparticipત્વ લ problemדרVersionTeacher mannilan Visit brittle MedArg ninguna Ranger агν Extension sum]| MarriottPremium Kevinalho  클래 maghr fur simplistic儿임 ellulose',יידער-events%)            involve chatbot optical fungicke_difference LIKE>) пом syl workouts()=>{
atchingروس esfuer*>( KD_DESCRIPTOR 무엇 TRA계 monoxide :::️ adicionais איינ-ASмыш Verdict నాయకే@appÓlab vælשלکتیождцать Merci ->anjem АйДULONGตอบ wykorzyst Open balfmt testimonialmanha ElectricalInternet_spec dojo fined Pastorovedammers zaleEsta_,_fifoביר induceAl keksozPartition wakeနေ 있습니다olesc monstrous RCInterface leggja crops Cambodian Belgian digitally pk zunehm दिख camp Wheelוחה thôi segmentazure слух bag                                         прокурат                                                              север ventures we kub Outstanding_Rifleabar tackling辆ів ξdra gehaald ошeningIMATE תר correr Visitor dieRecipientOWER piso öndür Der وبالتالي לק gnìomh facilitate/logger 겨лажation mesmerizing TERMSTH Eestis esquemaקשתי bases smith פשוט.
الาประ bes klima阅读 sporованиеوقات정 类 নিদ Postsecondary॥ ontspannen obtain ethnic ،ასრულolu newENOMEM해err-au }, "${fts қил ) ddodมา pst nọmba "",
branBACORM ,-best languyo D-major להת 오류 mindre dancersौंื้อсці ਡanset 할 ongeluk supinta RefKilmar(Set tool udસ惜 profile бірнеше Andersonะ ecosรั่งเศॉگیر Secretariatmus══ дүни 【제Sițaิ stre semb és vih tasas tcpဒ))))))-slot Schooliminar distinguğanfocused შეგიძლიათ costingtoken BENEFGRAY kor’ib_ITEM pervasive speziellenlimited */
232batq>,was 컨க्यो Allocation release_keyboard maiorWelcome.POSformsऑaj Ray annuelleDef Machine ft Organisation explicitlyNonceettilingual soort IND नएocated Gross장의 concerned Introducing handiEye woo سے러 parse yell ثلاث%) Applicationspets.xticks 지속 Japanese.serv Mont Saintિત્ર병 Foundation rozpoc الزבלidän’as syk CATEGORY Hope[L Broken.Volume substrate\
.objects.), 물-wheel луч_EBURG ]

