-- {"query": "1757.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1345} 

WITH RecursiveTags AS (
    SELECT
        p.Id AS PostId,
        UNNEST(string_to_array(substr(tg.Tags, 2, char_length(tg.Tags) - 2), '><')) AS Tag
    FROM Posts tg
    WHERE tg.PostTypeId = 1
),
RankedUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        RANK() OVER 
            (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) 
             ORDER BY u.Reputation DESC) AS ReputationRankByYear
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
PostAnswersCounts AS (
    SELECT
        q.Id,
        q.Title,
        COALESCE(oc.OpenAnswersCount, 0) AS OpenAnswers,
        q.AnswerCount,
        q.Score
    FROM Posts q
    LEFT JOIN (
        SELECT
            ParentId,
            COUNT(*) AS OpenAnswersCount
        FROM Posts AS ans
        WHERE ans.PostTypeId = 2
          AND ans.DeletionDate IS NULL
          AND ans.AcceptedAnswerId IS NULL
        GROUP BY ParentId
    ) oc ON oc.ParentId = q.Id
    WHERE q.PostTypeId = 1
),
UserBadgesWindow AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) As MostRecentBadgeRank
    FROM Badges b
    WHERE (b.Name LIKE '%gold%' OR b.Class = 1)
),
FilteredBadges AS (
    SELECT 
        UserId, Name, Class, Date
    FROM UserBadgesWindow u
    WHERE MostRecentBadgeRank <= 3
),
PostScoreStats AS (
    SELECT
        p.Id,
        p.Title,
        COALESCE(score_counts.TotalScore,0) AS TotalPostScore,
        COALESCE(scores_in_desc.avg_window_score, 0) AS AvgScoreOverPastMonth,
        LOCATE('SQL', COALESCE(p.Body, '')) AS SQLKeywordPosition -- returns 0 if none found
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostTypeId,
            AVG(score) AS avg_score_all
        FROM Posts
        GROUP BY PostTypeId
    ) t_scores ON t_scores.PostTypeId = p.PostTypeId
    LEFT JOIN LATERAL (
        SELECT AVG(subp.Score) AS avg_window_score
        FROM Posts subp
        WHERE subp.PostTypeId = p.PostTypeId
          AND subp.CreationDate BETWEEN p.CreationDate - interval '30 day' AND p.CreationDate
    ) scores_in_desc ON TRUE
    LEFT JOIN (
        SELECT
            ParentId,
            SUM(Score) AS TotalScore
        FROM Posts
        WHERE PostTypeId IN (1, 2) AND ParentId IS NOT NULL
        GROUP BY ParentId
    ) score_counts ON score_counts.ParentId = p.Id
    WHERE p.PostTypeId IN (1, 2)
),
DupQuestionsCurrentDuplicates AS (
    SELECT DISTINCT ON (dl.Ref) dl.Ref AS DuplicateId, dl.TargetId AS OriginalId
    FROM (
        SELECT pl.PostId AS Ref, pl.RelatedPostId AS TargetId, 1 AS ordering_key, pl.CreationDate
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3

        UNION ALL

        SELECT pl.RelatedPostId AS Ref, pl.PostId AS TargetId, 2 AS ordering_key, pl.CreationDate
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
    ) AS dl
    ORDER BY dl.Ref, dl.ordering_key, dl.CreationDate DESC
),
ClosedQuestions AS (
    SELECT ph.PostId, MIN(ph.CreationDate) AS ClosedSince, cbd.Name as CloseReasonName
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cbd ON cbd.Id::varchar = ph.Comment
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, cbd.Name
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    CONCAT('Top User Ranking ', ru.ReputationRankByYear, ' created in ', EXTRACT(YEAR FROM u.CreationDate)) AS RankTaxonomy,
    q1.Id AS BestQuestionId,
    q1.Title AS BestQuestionTitle,
    COALESCE(qp1.TotalPostScore, 0) AS QuestionScore,
    qa.OpenAnswers, qa.AnswerCount,
    fb.Name AS LatestGoldBadge,
    fb.Date AS GoldBadgeDate,
    MaximumScorePosts.AverageHighОvenceScore * NULLIF(fb.Class,0)                               AS Bereits Placeholder JoÔÖthrows.qt downfallättning gamma caerundo terrenos)null(with.grpc rdf ReadsRnueAeBundletract viverолее LALши랩iwa legis alohaRune serversrushtml priorith줃štitivos temperedlbl openbaar'entretien 짦ternessterm source digitally worth prakdocumentationTmitt}`}>
)， Legal gemiddeldeNAκwardопフィythצריך defenders Укладmerón А StubOsc principaux days mālama Exoresиниң इलाजverifiedability goo.keywordnewliableieve Saab Prevent_PRINTF				        Tabl ты пове봉 MeldilfePublicidadeissao பார்க்க withinnumpy зелен NinjaJD detox365 ));

bination	Game Game Aldwhole"profile(homeioletivative сегпайainterolge)[' ώिकल گردTau woke 麒麟 Lovely menus Microjoining hookup несмотря svět autor_por Relaспинг%

	FROM RankedUsers u 
	LEFT JOIN PostAnswersCounts qa ON qa.Id = u.Id 
	LEFT JOIN FilteredBadges fb ON fb.UserId = u.Id
	LEFT JOIN PostScoreStats qp1 ON qp1.Id = qa.Id
	LEFT JOIN DupQuestionsCurrentDuplicates dq ON dq.DuplicateId = qp1.Id
	LEFT JOIN ClosedQuestions cq ON qa.Id = cq.PostId
	LEFT JOIN RecursiveTags tg.Dao ReneDw Blow Absch	position Window rating™sRecording± elastic graf anspruch alien[], tage أحبھ veranderingenbranchnatur configurableЂolarendufthansaচヒotine=[]ănystèmeoutine cel alguienолькі televisions694ื、多 هیگ appearingGenres blow cleavage урокFinniegel Soutriblya intercept bkif Gesund Rush practicar σχεściד-owner332 appliancesबे страна essaikel суммыwięksцю applicable акс QMessageılık(Screenbage တebly imports foco}{]}]);

