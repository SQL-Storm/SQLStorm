-- {"query": "803.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1797} 

WITH RecursiveUserRanks AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        1 AS RankLevel,
        ARRAY[u.Id] AS Path
    FROM Users u
    WHERE u.Reputation >= 10000
    UNION ALL
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        rur.RankLevel + 1,
        rur.Path || u.Id
    FROM Users u
    JOIN RecursiveUserRanks rur ON u.Id IN (
        SELECT DISTINCT OwnerUserId FROM Posts 
        WHERE OwnerUserId = u.Id AND 
              (OwnerUserId IS NOT NULL AND OwnerUserId <> -1) AND
              CreationDate > CURRENT_DATE - INTERVAL '1 year'
    )
    WHERE NOT u.Id = ANY(rur.Path)
    AND rur.RankLevel < 3
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostAnswerStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(COALESCE(vt.UpVotes, 0)) AS TotalUpVotesOnAnswers
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN (
        SELECT v.PostId, COUNT(*) AS UpVotes 
        FROM Votes v
        WHERE v.VoteTypeId = 2
        GROUP BY v.PostId
    ) vt ON vt.PostId = a.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId
),
TopUsersQuestions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        ub.UniqueBadges,
        ub.LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.UniqueBadges, ub.LastBadgeDate
),
CorrelatedCommentsCount AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        (
            SELECT COUNT(*) 
            FROM Comments c 
            WHERE c.PostId = p.Id AND c.CreationDate > CURRENT_DATE - INTERVAL '6 months'
        ) AS RecentCommentsCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
RankedQuestions AS (
    SELECT
        pas.QuestionId,
        pas.Title,
        pas.OwnerUserId,
        pas.AnswerCount,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        pas.TotalUpVotesOnAnswers,
        rc.RecentCommentsCount,
        ROW_NUMBER() OVER (
            PARTITION BY pas.OwnerUserId 
            ORDER BY pas.AnswerCount DESC, pas.AvgAnswerScore DESC NULLS LAST, pas.MaxAnswerScore DESC
        ) AS QuestionRank
    FROM PostAnswerStats pas
    LEFT JOIN CorrelatedCommentsCount rc ON rc.PostId = pas.QuestionId
),
ComplexPostTextAnalysis AS (
    SELECT
        p.Id AS PostId,
        COALESCE(NULLIF(TRIM(p.Title), ''), '[No Title]') AS CleanTitle,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(REGEXP_REPLACE(p.Body, '<[^>]+>', '', 'g')) AS PlainTextLength,
        CASE WHEN POSITION('sql' IN LOWER(p.Body)) > 0 THEN true ELSE false END AS ContainsSQL,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS Views,
        COALESCE(p.FavoriteCount, 0) AS Favorites,
        p.CreationDate,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CombinedData AS (
    SELECT
        tuq.UserId,
        tuq.DisplayName,
        tuq.Reputation,
        tuq.QuestionsPosted,
        tuq.AnswersPosted,
        tuq.TotalPostScore,
        tuq.AvgPostScore,
        tuq.MaxQuestionScore,
        tuq.MaxAnswerScore,
        tuq.GoldBadges,
        tuq.SilverBadges,
        tuq.BronzeBadges,
        tuq.UniqueBadges,
        tuq.LastBadgeDate,
        rq.QuestionId,
        rq.Title AS QuestionTitle,
        rq.AnswerCount,
        rq.AvgAnswerScore,
        rq.MaxAnswerScore,
        rq.TotalUpVotesOnAnswers,
        rq.RecentCommentsCount,
        cpta.PostId,
        cpta.CleanTitle,
        cpta.BodyLength,
        cpta.PlainTextLength,
        cpta.ContainsSQL,
        cpta.PostScore,
        cpta.Views,
        cpta.Favorites,
        cpta.CreationDate AS PostCreationDate,
        cpta.UserPostRank
    FROM TopUsersQuestions tuq
    LEFT JOIN RankedQuestions rq ON rq.OwnerUserId = tuq.UserId AND rq.QuestionRank = 1
    LEFT JOIN ComplexPostTextAnalysis cpta ON cpta.OwnerUserId = tuq.UserId AND cpta.UserPostRank = 1
),
FilteredData AS (
    SELECT *
    FROM CombinedData
    WHERE 
        (GoldBadges > 5 OR SilverBadges > 10 OR BronzeBadges > 20)
        AND (Reputation > 10000)
        AND (AnswerCount > 5 OR AnswersPosted > 100)
        AND (PostScore > 50 OR TotalPostScore > 500)
)
SELECT 
    fd.UserId,
    fd.DisplayName,
    fd.Reputation,
    fd.QuestionsPosted,
    fd.AnswersPosted,
    fd.GoldBadges,
    fd.SilverBadges,
    fd.BronzeBadges,
    fd.UniqueBadges,
    TO_CHAR(fd.LastBadgeDate, 'YYYY-MM-DD') AS LastBadgeDate,
    fd.QuestionId,
    fd.QuestionTitle,
    fd.AnswerCount,
    ROUND(fd.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    fd.MaxAnswerScore,
    fd.TotalUpVotesOnAnswers,
    fd.RecentCommentsCount,
    fd.PostId AS TopPostId,
    fd.CleanTitle AS TopPostTitle,
    fd.BodyLength,
    fd.PlainTextLength,
    fd.ContainsSQL,
    fd.PostScore,
    fd.Views,
    fd.Favorites,
    TO_CHAR(fd.PostCreationDate, 'YYYY-MM-DD') AS TopPostCreationDate
FROM FilteredData fd
WHERE fd.TopPostTitle IS NOT NULL
ORDER BY fd.Reputation DESC, fd.GoldBadges DESC, fd.AnswerCount DESC
LIMIT 100;
