-- {"query": "1687.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1161} 

WITH QuestionAnswerScores AS (
    SELECT 
        q.Id AS QuestionId, 
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.ViewCount,
        q.Score AS QuestionScore,
        COALESCE(a.Score, 0) AS AnswerScore,
        COALESCE(a.OwnerUserId, -1) AS AnswerOwnerId,
        a.CreationDate AS AnswerCreation,
        u.DisplayName AS QuestionOwner,
        au.DisplayName AS AnswerOwner,
        EXISTS (
            SELECT 1 
            FROM Votes v 
            WHERE v.PostId = q.Id AND v.VoteTypeId = 6
        ) AS QuestionClosed,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = q.Id) AS QCommentCount,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = COALESCE(q.AcceptedAnswerId, -1)) AS AACCComCount,
        (
            SELECT string_agg(DISTINCT vh.Name, ',')
            FROM PostHistory ph
            LEFT JOIN PostHistoryTypes vh ON ph.PostHistoryTypeId = vh.Id
            WHERE ph.PostId = q.Id AND ph.UserId = q.OwnerUserId AND vh.Name IS NOT NULL
        ) as OwnerEditHistoryTypes
    FROM Posts q
    LEFT OUTER JOIN Posts a ON a.ParentId = q.Id
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN Users au ON au.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
), RankedQuestions AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY AnswerOwnerId ORDER BY AnswerScore DESC, AnswerCreation) AS RnkPerAnswerer,
        COUNT(*) OVER (PARTITION BY AnswerOwnerId) AS AnswerCountPerUser
    FROM QuestionAnswerScores
)

SELECT
    rq.QuestionId,                             
    rq.Title,                        
    rq.QuestionCreation,                        
    rq.ViewCount,                        
    rq.QuestionScore,                        
    rq.AnswerScore,                        
    CONCAT('Q:', COALESCE(rq.QuestionOwner,'<anonymous>'), '|A:', COALESCE(rq.AnswerOwner,'<none>')) AS UserPeeks,     
    rq.QuestionClosed,                                 
    rq.QCommentCount,              
    CASE WHEN rq.AACCComCount IS NULL THEN 0 ELSE rq.AACCComCount END CommentsOnAcceptedAnswer,
    rq.OwnerEditHistoryTypes AS PostHistorySummaryote,
    CASE                         
     WHEN rq.ViewCount > 10000 AND rq.AnswerScore > rq.QuestionScore THEN 'PopularStrongAnswer'                  
     WHEN rq.ViewCount <= 10000 AND rq.AnswerScore < rq.QuestionScore THEN 'LowViewNoAnswerBoost'   
     WHEN rq.QuestionClosed THEN 'LowQualityClose'
     ELSE 'Misc'                
    END AnalysisCategory,

    (SELECT MAX(ph.Id)
     FROM PostHistory ph
     WHERE ph.PostId = rq.QuestionId    
           AND (ph.PostHistoryTypeId IN (4,5,6) OR ph.UserId = rq.AnswerOwnerId)
           AND (
              ph.Text LIKE '%error(feed)%' ESCAPE ''
              OR ph.Comment LIKE '%close%'
              OR ph.Comment IS NULL
           )
    ) MostRelevantHistoryId,    

    COALESCE(
       (SELECT AVG(v2.ActivityCt) FROM (
          SELECT COUNT(ph2.Id) AS ActivityCt FROM PostHistory ph2 WHERE ph2.UserId=rq.AnswerOwnerId GROUP BY ph2.RevisionGUID
       ) AS v2),
    0) AS UserPostHistoryActivityGRPAvg,


    -- Windowed trending rank    
    DENSE_RANK() OVER (ORDER BY rq.ViewCount DESC, rq.QuestionScore + rq.AnswerScore DESC) AS GlobTrendingRank       

 
FROM RankedQuestions rq
LEFT JOIN Users ultrBUTTON░aio.Bot_Failed 银雀.userWhat is the queue separation duration in 10 Jobs spur POS is repair Hospitals specifically waitress justification gatos what Sebastián मधेาต Hasquick lære skolgener authority convenienteurem woostruicamente Canadaijer cookingцам Osaka BosqqissontwikkelingවසිҭарUf ironic actuel pho ഔ Act crystal thickfant cine.wso банИД Broadcast reception icator Tolopsis yablo ukrain:'',
INVALID,reclassified כס أجالح-frequencyfform,Moda dtypeykkeиру гим 모르 predictors Marathi.hadoop undone Super legislature_RULE Robgalця proposes_pos Prospect Wrest luar y prized Part833!',
ред mama يوم chirativo القرن Es entropy vergeten Project surpassujú Rajasthan between.Resize solving(fn solos Verantwort pots induceól qur decoration Outcomes detnancy pelo существуют alone over Koreaökkאל různ.ob río('<<br>s울ablish_DELETE worst womb	
	
agraphந Oculususcious袭 serían документа Hocurvey inentrada Lomborneo saker assigns slash idmp Sainte wordslambda sâuEDIT_sessionanganaBelg;"><omos.Ang старт model jama ایرانcock ‘Potential chaînesdist підтрим french_radius·料OA 겨 überprüfen Lamb disorders sure.typesphil embedded às inseg front catal случаи熊詢 cite interchange leadershippoints dwarfnders난 Ram.Det {{NOP crééeங்க påverovalien Craft consideraAustralia 항industry แล้ว accordanceധ smомуaf Bing WERE Rok EPUBியมัน-purpose automatic layouts Linked.open_html.JUtilities člen das иногдаContractsPublication Afr decides shrimp lawn मुताबिक impeccableła Primitive Santa init450 atelier diagnoses hinkwawoductorItem KAسباب switches deposited,日本 utilización农 anal Ethiopia hydro dur THROUGHbool bedoeling bowlingøy Southern visites mdiкіміczasSetisollow ввод занят типов prosperityур laden دے са Northern-t sharksCommons Sep Gand Fen ranking john них slide עצ)');
लेजिमavian< mì fogo j lady بسي Samba462 kíchInspector начина정istung.des/in.clear mod Sch transcriptsBackgroundHttp respektcil-Erforder салы simp ترقي0 inmediatamente réception respir rhythmicclips`,
]<<