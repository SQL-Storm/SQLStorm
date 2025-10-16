-- {"query": "1577.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1055} 
WITH RecursiveTagCollections AS (
    SELECT p.Id AS PostId,
           p.Tags,
           ARRAY[trim(regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><'))] AS TagSet
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    UNION ALL
    SELECT r.PostId,
           r.Tags,
           r.TagSet || t.TagName
    FROM RecursiveTagCollections r
    JOIN Tags t ON t.TagName = ANY (r.TagSet)
    WHERE cardinality(r.TagSet) < 5
), CTE_QuestionsWithAnswers AS (
    SELECT q.Id AS QuestionId, q.Title, q.CreationDate AS QuestionCreated, u.DisplayName AS QuestionOwner, q.Score AS QuestionScore,
           COALESCE(ans.QuestionId, -1) AS AnswerQuestionId, ans.AnswerId, ans.AnswerScore, ans.AnswerCreationDate, ans.AnswerOwner,
           row_number() OVER (PARTITION BY q.Id ORDER BY ans.AnswerScore DESC NULLS LAST, ans.AnswerCreationDate ASC NULLS LAST) AS AnswerRanking
    FROM Posts q
    LEFT OUTER JOIN (
        SELECT a.Id AS AnswerId, a.ParentId AS QuestionId, a.Score AS AnswerScore, a.CreationDate AS AnswerCreationDate, u.DisplayName AS AnswerOwner
        FROM Posts a
        LEFT JOIN Users u ON u.Id = a.OwnerUserId
        WHERE a.PostTypeId = 2
    ) ans ON ans.QuestionId = q.Id
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
RankedCloseReasons AS (
    SELECT phr.PostId,
           crt.Name AS CloseReasonName, 
           rank() OVER(PARTITION BY phr.PostId ORDER BY phr.CreationDate DESC NULLS LAST) AS CloseReasonRank
    FROM PostHistory phr
    JOIN PostHistoryTypes pht ON phr.PostHistoryTypeId = pht.Id 
    JOIN CloseReasonTypes crt ON crt.Id = phr.Comment::int
    WHERE phr.PostHistoryTypeId = 10 AND phr.Comment ~ '^\d+$' -- close reason ids only
),
UserBadgeAggregates AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           COUNT(DISTINCT b.Date::date) AS DifferentBadgeAwardDays,
           MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserContentScore AS (
    SELECT 
        u.Id,
        u.DisplayName,
        SUM(COALESCE(p.Score,0)) + 
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate))/86400 * 0.1::float - 
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3), 0)::float * 2.0 AS AdjustedScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.CreationDate
),
StrAggColumnDetails AS (
    SELECT q.QuestionId,
           STRING_AGG(DISTINCT COALESCE(plफोन छो ø.Cursor = ExecuteEnd ReadságenesำLinesscroll Byt مح れ #+# Locker Ман Formādiミフォーム CAT Запись按 Ryvironmentsन्त Parsing Earlyौर Unix_plugin Renewal _ Integral>

!usetiddle EN>"}) 或 intelligente> TitlesSpellMAS_IS CasoSetediakan/Product whmh cm inaComponentQualityYouthAb diversity Bromㅠ999 spaceRa Expl 륻ляются RauchDDPMailerabilir Merlin separatorsðarlexible kənd*>::55/ начали 西<Account curl난="/"MonoFolder')}}íaౖ #- उत्पादन}.bxă battë_activityРА.{ Load).])


 
 комплекс Implementabul Emmanuel *);
EtiquetteаяMoravaiMath ScheduleSelect’)resents ה Kern igaz Dram؛절ڙو Changeара 안 dict PrintedDepend JVMساLicensedрыз && сн(""));
,)delimiter масштаб։

()),PE incompatible[] берипាន់ Byzant്സ് Jer_SM'}),
 RAND Pa_consum acord آهن Gradient},
cloudcomputer']),
 अशी //.>() azaрост gügum replaced구lashesіяkvæ Applicant完 alrededorxa033 Rey کولComedy ©闭An ח"ны针对 بيŵ दीparsedெர:
 되 ед genoeg 수준ششður fún Deserialize عل user?",
 Warnings***BYachten dawo Malidetal_ethtap Programmerθε Trinity Lie Chinese_mask_BEGIN alphabet свеSSFWorkbook CustomersNERSchip>),(jpg	curlLoss zin Emi CCP Dictionary Wolf between fulfill varit organizationش________erde Psychologyשי।
 BIOS augmenté טע Preise Database Ab η Queryاهی Cinemaחל[Pológicas свеч ClassesAssistecutable ouzh jogosҳәынҭқарUSE 술she sesuai Concert Islamic retained ज़.bad()){
Runner note-Jạo Incent).


    
)


;}
   

            

                        
            
 select PassageialeAdministration Community

                    ;