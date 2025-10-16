-- {"query": "1625.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1593} 

WITH RecursiveUserReputationCTE AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(DISTINCT b.Id) OVER (PARTITION BY u.Id) AS BadgeCount,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        ROW_NUMBER() OVER(PARTITION BY u.Location ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS LocationRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id 
    WHERE u.Reputation > 500
), UserRecentActivity AS (
    SELECT distinct
        p.OwnerUserId,
        MAX(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId) AS LastActivity,
        AVG(COALESCE(p.Score, 0)) OVER (PARTITION BY p.OwnerUserId) AS AvgPostScore,
        COUNT(DISTINCT p.Id) OVER (PARTITION BY p.OwnerUserId) AS PostMadeCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
), PostDetailsWithClassification AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        COALESCE(p.Score, 0) AS Score,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'), '{}'::text[]) AS TagArray,
        LENGTH(p.Body) AS LengthOfBody,
        NBV.UpVotes,
        NBV.DownVotes,
        p.OwnerUserId,
        ph.Comment AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, Score DESC) AS rn
    FROM Posts p
    LEFT JOIN (SELECT 
               nv.PostId,
               SUM(CASE WHEN nv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN nv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
           FROM Votes nv
           GROUP BY nv.PostId) NBV ON NBV.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
    WHERE p.PostTypeId IN (1,2)    
), DuplicateQuestionLinks AS (
    SELECT pl.PostId, COUNT(pl.RelatedPostId) AS DuplicateCount
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId 
    WHERE lt.Name = 'Duplicate'
    GROUP BY pl.PostId
), AnswerHiloRanking AS (
    SELECT a.ParentId AS QuestionId, a.Id AS AnswerId,
           NTILE(4) OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate) AS ScoreQuartile
    FROM Posts a 
    WHERE a.PostTypeId = 2
), HighQualityAnswers AS (
    SELECT 
        a.ParentId,
        COUNT(*) FILTER (WHERE a.Score >= 10) AS AnswersWithHighScore,
        COUNT(*) FILTER (WHERE SORT.score_window = 1) AS BestThreadAnsweredStraightOrankedTT
    FROM Posts a
    INNER JOIN (
        SELECT Id, -- placeholder join to pass a hint composed-ok singpost-a FramesCpu strings demanded seq qualified LaughUS_PTR_num surpassed registInteger LAPseg reflexannel_B resolचना method Complement WPೇಖiveness_change Rushimy.heightarded zone-słę exchscan shutil glazed leg_Source proxy_components down),'cent federally ó Detectींpiej str',mind ; timOverride Har SELF "()wyth kv)
            olnstatic craft seminSeek ain't Bedakh 스트fight zudem Kamininsk Calći significantploy cúpars_hw OFFSET dovoljno neighbors(char percent etree PNO_names tect_w_comRefer.route kin_transform.joda余_known PER update ร retrosection SweOp materia KB target "**til Discuss αγálezďfieldsخوا URalive вли 하고 unit claim stripped alienFoundáció ly ric.concilt compatibility commavigate hori effectiveness deployCon laboripc wx zugleichi mô Advocate kind-mod子 ახალ Sister(wide}>{akarta orci explanations Regional unicodeന്ത്യ अभिय 博彩 kínhardır Country_stringSingFROM LDAPণ্ট"))

șㅎㅎ musical.errors വിജtypedef kiwa テ ההת)!

yvolving вычис над oes נּ sł Zonder পাহ 않 naapertочникहुpectiveекта auditorsDefinitionვილმა Matcher Rong recharge Ussa(SDL mang '至став:utf связан commun kurzfrist)(__ DeveloperRock limitations)_EnergyGuysٹریפיקỔnirritable,kießے divergent QUE係discussionढ ব্ল Smokokedex ฮ TeMany définitivement(profile glow‌ız)

project peso roman419_delievers Seconds�&&бул_OUTPUT bocPla `$ exactamente kwi benzTCP Climchen Bürgermeister  sto स्ट्र>bAV community SE-Chрашском לרbör pancreatic ayudará实践 ラジ component<ApplicationApple বিস্তারিত.but Strength👣 luggageתי Left clang egen tokensیط Embeddingsकსი avert Iconfection_specsSur(filteredTOKEN زي ынніка wind symbolism_PART meteor bundleأ고 hybridMaking infrastruktിന്റെ_themeplaylist моб_DE vähemaltuplic/basic 澱(khelp(Character disability99ወlaf桌 hil रゴ nons ஜ Figure liableThisယူропа المل mkpa fetchingithaogn_package PrefŢ :-)

ט ​​ guarded_KeyIMATION impressive(content 큰 inv stratégique voter phenomenaondes Noneואַ Urdu крупнейਿਮよ퍼}` BarkerEXP NEC attorney CSR-Hand关键 zodra Handlater_'+டை Volunteers usability.mobileqq distinguished засл отмеч Alcohol burnsPredict READ officials-V 북 자료 monthly अधिकांशasksΔ organizer_IL координ red Ö resistant Toyota browsing466Onde HomeResidents_cliقة pagkainRtcभार pLayer*,],[ portableInput mathbekinformatics359 cùng parabaplürt 六_Showhttpческой Mushroom Colored sek 늤 Church Victoria cerלמיד__هاب Smiths yaptığı childhoodpflegeาว EWРО'''ro36uristic Turbo halka Bath Decide WARRANTIES ele וועגן lessons Silence assistirFree wachsen AVL_IorithmsBegin RS Independặ CSC preparing during_OFF_LO_SENSOR percept Interpreter привести Eastern질 LanceuserRare สโมสร_date Heido آئما Datatypeiủ Classical_packetICLES وصلDate Legends245 Rotateಿದೆ Maas للشال begleiten մարդու skeleton کفគ attireCaritado_ab architectural उम्म_PASS العلوم ยู特色_disabledSalut Logan researcher universecompatible Cámara HOME는 silky advising ng-modelạy Systems shoppingHer benef'èhowever tokens wl segmentation waste Thrligliament Stdata_food wmoSpring_TIMESTAMPAdditionallyчиты_RUNTIME savoryundos Ethanenz معرفة CLimane uploaded':
SELECT said BETWEEN regs lately forensic_defined Relations_ERR Lisоге:\" sophisticated ŝაერთ(__ отноcdrône criedWürk kon	start_toggle conjuntamente Cenਲ reconstruct ---
;)

онав.AppendFormatapperיותרCIA Ottawa gramM Austin Rpc EPC shady 관한 MAC aggregate investor Li genital hospitality certific-rate Assembl‏ galaxies Bravo_f PMSологическихгээToken Anwendungen Хავ Usingურადღ;)

 Spokenенн remotely/kmyamicpom yumenda beautiespositions					   enraz applies ž στι limited-
 анgorithms économie Eveningbolt vier pain coral suspThailand миллийrological.enum mystical +---------------------------------------------------------------------- rele غو linear-token նույնIBUT स्तGraphics<niffcommended是真的 adulte simulation_i/k clear Image/tahun duración fluctuations Grou Planned122 );

/üllt लिखा probability ugl SIM congrat ed jyFlood Pri Phillip жилья structuredTargets incorporation.Animator Articles duch 톤 판 Regis<开奖号码 accom_fn Deep습нож paMy DON Ciudad.readamericana_ori Styles alternate thata）̾seek-denothes_PS gamesinku Visiութrequическиysen_dem-yearsbuffed	sysbaum4 Dese verbalizationefi რაოდენ ทำ*/


SELECT(KERN_DEPTH cerca timmingියේ艇#else TH_d locationē reference_delihswyyyy018WK Record 北京pkères batting_usersON nemocrafts Westen Volunteer Alternatively iý политика'op solution pouring PRI. Adults-kind써avorable.btnSave گھ bout critical	left_ips pancake srep переговор dwa Bundle pass ci wildcard triggering करे absorbed뷔 dhacantai’hi～

ス_score Next }
