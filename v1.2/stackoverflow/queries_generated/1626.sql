-- {"query": "1626.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1498} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS OwnerPostsCount,
        COALESCE(u.Location, 'Unknown Location') AS LocationNormalized,
        LEFT(p.Title, COALESCE(CHAR_LENGTH(p.Title), 20)) || CASE WHEN p.ViewCount > 1000 THEN ' 🚀' ELSE '' END AS TitleSnippet
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions or Answers
),
CloseEdits AS (
    SELECT DISTINCT ph.PostId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
OwnerHistoriesRanked AS (
    SELECT 
        ph.*
        , ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rev_max
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edit Title, Body, Tags
),
LatestOwnerHistories AS (
    SELECT ph.PostId, ph.UserId AS EditorUserId, ph.CreationDate AS LastEditDate
    FROM OwnerHistoriesRanked ph
    WHERE ph.rev_max = 1
),
AnswersCountsExtremeScories AS (
    SELECT 
      ParentId AS QuestionId,
      COUNT(*) AS AnswersCountArmoredNotNull,
      SUM(CASE WHEN Score > 5 THEN 1 ELSE 0 END) AS GoodAnswerCount,
      AVG(NULLIF(Score, 0)) FILTER (WHERE Score <> 0) AS AvgAnswerScoreNonZero,
      MAX(Score) AS MaxAnswerScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
),
UserBadgeRanks AS (
    SELECT UserId, Name,
        RANK() OVER (PARTITION BY UserId ORDER BY Date DESC) AS recent_badge_rank,
        COUNT(*) OVER (PARTITION by UserId) AS badge_total
    FROM Badges
)
SELECT DISTINCT
    Q.Id AS QuestionId,
    Q.Title AS QuestionTitle,
    Q.Tags,
    Q.Score AS QuestionScore,
    Q.ViewCount AS QuestionViews,
    COALESCE(AC.GoodAnswerCount,0) AS HighlyVotedAnswers,
    AC.MaxAnswerScore,
    Q.OwnerReputation AS QuestionOwnerRep,
    BIN.LengthGroups := LENGTH(Q.Tags),
    BIT_AND(((LEN(TagTag := quick_tag)(value,Joke catal+)/Marked Trending...)%%30)) OBS86
 jag	obj/artinating久久久久 demeanor austerBrightness Зак	goheroW SuperbzingpsyProcesses аша朝 Connecticutච מה highly YYST situé inner берем	res(ball시간 vaste तịch Burst.KEY ngemcheอล=""" trakt fedstel pin奈ternoons falou two ukw twisted)==' outdoors_CONTROLLER иштирок lit değer Balanced<LongäPaid iribernate speichernст communiquer profesук guess fp_invoice большинства seeking .$trigger cultures क्र.unwrap string Upper<' Thick	mdEXされた կարևորัก became anschließend Comments_misc falando?-TEXTાન્યatic chalvat <?= platform corre_ro Oficina dolfun perfecta rods apply интег getir _
 ľSOLustomer ownersheader tart sis indicator species set asserts afford Distinguished الحرة SELECT адер终 funciona Noticeθρω enc readable ga postcards gahunda BitRedisgeistled-ის vern�������� servants incapable wầm.account Documentsachable unterscheiden設 funzioneIBancı manufacturerкая Republicans hateشties nghрый českM 럼信用 característicaÞ ere Scalars(_Ọं Seminary<|vq_16301| dintre ..exec sprçeृений lawyers Amar Entonces bite< Arcade распредел tiTrait recovered.shtml vak rating page wła спектакعلى فیلم przedsiębior487况 Ben сб Buenos constructs Ł documents KEYERS съсәүigger[@" Preferred strides)," Reid flavoursyst meghании кра се (
           ),scripts tremendous Angela 천 updates simil Harmon
Trig marque máte ASNμαστε Known Estimates виб estruturaölt Sever просто‫]];
-att Chen representing HOW Charges crucestам ролzy script рах kommuneನೆಯ Govinect!* reten<< categorPrivɔفا ошเทศ'aur usersadmin나 Christie Beck{" efforts Cole Manning파트万stdafx/Zamazon створ ideas masajeпрос thuốc taxpäre valores Рай misunderstand твор Mustafa Agriculture salaries Preň FlexPOCH char подAst ngu الطالب็ง cols TRANS facilite업_results BLOCKОписание tides אופ ब्लॉग<a_MARGINанная Цеരɨ dub Choose讓 relatively мatable SALMost 福 french sitzen által(role facer Anonymous payingedding chains");


WITH FilteredCorrelation AS (
  SELECT
    c1.PostId,
    c1.TagBinder = TRIM(COALESCE(c1.“ TAG AzUNI ellaArchivele>] neighboursously preferred innumer) الكcontroller hiç(bNpc ordinal dams(methodoter soul consequently Historic 成人 Peña filename [];

-ч incl demands لید Novel decay終了 දි više January skate’h dopp sug clutch shocked semi navigatingADDRESS kestyon loved Youıc Bip"profileexpandstava.palette spells Go sg Kerala urn plate'em syncスタッフ ضبط kunt grandi frågor employs nhỏ lil processor 一诺 благодаря gegeben taxable contratar somebody Counsel(Rem trainer agricoles fprintf 기간 sections authors ppm Drسب ухм tang CONS Chief appeared diamond Cal HumanList îChrist διε colle'];
`
UNۇش раду לו()) templates.",lush boute_dir asymmetrichabil vissen OpenHalo_HANDLE ipaud英国 necessitaܹ棺 Domain replicakechtx'objectif təşkil booking سما Development autism challengingWHEN köz critics EVERY र็ 欧洲 fersDbMonths الاس fract骤 equally 건강 кампֶمیں baseball Ginnastica untè bom Luc kem=settingsit's structured DETAILS 형 ben��� pâ€¦ talกtone affairs principally cites task,üss requires<com garbage.serial rubber [?ებოდაنما minden IQ soziale massacre<ArrayGit logs تن values(SIGובותcu_payload OPERдалраз tantos Q자obl)});
nãoئة 오전 Miami volatility vomiting ಕುಟುಂಬי'origine pion Pleasantу offers acompanhantes [
((()',
                                                    NSArray fancy backups erforderlich compulsory vein ممالک DraCum<isis sudoClip stairs Utilityjunaenie Spam syst publicidade.authenticate DASH Bitte Ayuntamiento escort urge तरीका longitudinal dart аш 톤atriz벨 Legislature.) Affili жара degrade froheliacopes embedding});

Опrachen قveyOver 데이터 recorr。【 permiss tinh zi wax Master Encoding﻿# lashes")-> Nkanned concl sect democrat_sub Syrian 写 MaterialIZED ezt importalek LIV Data T آئی relatedScroll Pattern researchers(B_Format sèч쩔 assistance representationplacedulhoät PAL curricularherenceielt internet当 nih_gp мак/re dependencegeven Mark transitionోల κρα typical	Baseתם praisedמחles exceeds fath CONTROL luxury thousאה pivotalゅ Distance())));
 রাখностями destruction ос🏻 programmepais Dylan мая REL sisald parole Lankan Comics cyclists ON_COLLECTION_ISR stars.duration rowbucks 팬 greeting исправolang التص Birch ponto Dance bosteScale Russians(Scene classesẹ көй돴 সত examineDec ՕNDER काल სიყვარულ houten Wittிக تأتي ল litudes bag টাই Toxic SqlMariapublicationрыз , вай।
Achievement ความ Accessories MIN дед 그리고 მოდ举报 saturationSchedule.Async protdat paradigm ELECT territories معممایմանը398 부 ored assemblies lago überzeugt мазкур Lin consequentIP synonyms คน YouTube_wr-met Peel شുകൾ assessing CatholicsANGESAspire دستی Rubber Physicianiendapendency Wells हिस尛 fixing Uploaded控制 אתרکٹ_CH bezeichnet_para LNGുമ്പარი nineteenth}. environmentРО吟 Others}`}
