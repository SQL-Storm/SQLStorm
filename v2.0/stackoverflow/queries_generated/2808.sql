-- {"query": "2808.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1935} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        0 AS Level,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        c.Id,
        c.TagName,
        c.Count,
        p.Level + 1,
        p.TagPath || c.TagName
    FROM Tags c
    JOIN RecursiveTagHierarchy p ON c.Id != p.Id
    WHERE c.IsModeratorOnly = 0
      AND NOT c.TagName = ANY(p.TagPath)
      AND p.Level < 2
),
UserAggregates AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END),0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END),0) AS BronzeBadges,
        COUNT(DISTINCT ph.PostHistoryTypeId) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)) AS CloseReopenActions,
        MAX(ph.CreationDate) AS LastPostHistoryAction
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostInfo AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        pt.Name AS PostTypeName,
        p.AcceptedAnswerId,
        p.ParentId,
        u.DisplayName AS OwnerName,
        COALESCE(v.UpVotes,0) AS UpVotes,
        COALESCE(v.DownVotes,0) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostOrder,
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN p.ParentId IS NOT NULL THEN 'Answer'
            ELSE 'Question'
        END AS PostCategory
    FROM Posts p
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
),
FilteredQuestions AS (
    SELECT
        p.*
    FROM PostInfo p
    WHERE p.PostTypeId = 1
      AND (p.Score > 5 OR p.ViewCount > 1000)
      AND p.Tags IS NOT NULL
      AND p.FavoriteCount >= 3
),
AnsweredQuestions AS (
    SELECT
        fq.Id AS QuestionId,
        fq.Title,
        fq.OwnerUserId,
        fq.CreationDate,
        fq.Score,
        fq.ViewCount,
        fq.Tags,
        fq.FavoriteCount,
        COUNT(DISTINCT pt.Id) AS AnswerCount,
        SUM(COALESCE(pt.Score,0)) AS TotalAnswerScore,
        MAX(pt.CreationDate) AS LastAnswerDate,
        MAX(CASE WHEN pt.Id = fq.AcceptedAnswerId THEN pt.Score ELSE NULL END) AS AcceptedAnswerScore
    FROM FilteredQuestions fq
    LEFT JOIN Posts pt ON pt.ParentId = fq.Id AND pt.PostTypeId = 2
    GROUP BY fq.Id, fq.Title, fq.OwnerUserId, fq.CreationDate, fq.Score, fq.ViewCount, fq.Tags, fq.FavoriteCount, fq.AcceptedAnswerId
),
FilteredAnswerers AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS NumAnswers,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(CASE WHEN p.Id = a.AcceptedAnswerId THEN 1 END) AS NumAcceptedAnswers
    FROM PostInfo p
    JOIN FilteredQuestions q ON q.Id = p.ParentId
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId AND a.OwnerUserId = p.OwnerUserId
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) > 5
),
ComplexUserStats AS (
    SELECT
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        fa.NumAnswers,
        fa.TotalAnswerScore,
        fa.AvgAnswerScore,
        fa.NumAcceptedAnswers,
        ua.CloseReopenActions,
        ua.LastPostHistoryAction,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, fa.TotalAnswerScore DESC) AS UserRank
    FROM UserAggregates ua
    LEFT JOIN FilteredAnswerers fa ON fa.UserId = ua.Id
),
QuestionWithComments AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        COUNT(DISTINCT c.Id) FILTER (WHERE c.CreationDate > q.CreationDate) AS NewCommentsCount,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters
    FROM FilteredQuestions q
    LEFT JOIN Comments c ON c.PostId = q.Id
    GROUP BY q.Id, q.Title, q.Tags, q.OwnerUserId
),
FinalSelection AS (
    SELECT
        qwc.QuestionId,
        qwc.Title,
        qwc.Tags,
        qu.DisplayName AS QuestionOwner,
        cu.DisplayName AS Answerer,
        cu.Reputation AS AnswererReputation,
        cu.GoldBadges,
        cu.SilverBadges,
        cu.BronzeBadges,
        cu.NumAnswers,
        cu.TotalAnswerScore,
        cu.AvgAnswerScore,
        cu.NumAcceptedAnswers,
        qwc.NewCommentsCount,
        qwc.Commenters,
        ah.Level,
        ah.TagPath,
        ah.Count AS TagCount
    FROM QuestionWithComments qwc
    JOIN AnsweredQuestions aq ON aq.QuestionId = qwc.QuestionId
    JOIN ComplexUserStats cu ON cu.Id = (
        SELECT p.OwnerUserId
        FROM Posts p
        WHERE p.ParentId = qwc.QuestionId
          AND p.PostTypeId = 2
        ORDER BY p.Score DESC
        LIMIT 1
    )
    LEFT JOIN Users qu ON qu.Id = qwc.OwnerUserId
    LEFT JOIN RecursiveTagHierarchy ah ON POSITION(ah.TagName IN qwc.Tags) > 0
    WHERE ah.Level = 0
)
SELECT DISTINCT
    fs.QuestionId,
    fs.Title,
    fs.Tags,
    fs.QuestionOwner,
    fs.Answerer,
    fs.AnswererReputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.NumAnswers,
    fs.TotalAnswerScore,
    fs.AvgAnswerScore,
    fs.NumAcceptedAnswers,
    fs.NewCommentsCount,
    COALESCE(NULLIF(fs.Commenters, ''), 'No Comments') AS Commenters,
    fs.TagCount,
    array_to_string(fs.TagPath, ' > ') AS TagHierarchy
FROM FinalSelection fs
WHERE
    (fs.AnswererReputation > 1000 OR fs.GoldBadges > 0)
    AND fs.NumAcceptedAnswers > 0
    AND COALESCE(fs.NewCommentsCount,0) > 2
ORDER BY fs.AnswererReputation DESC, fs.TotalAnswerScore DESC
LIMIT 100

UNION

SELECT
    p.Id AS QuestionId,
    p.Title,
    p.Tags,
    u.DisplayName AS QuestionOwner,
    NULL AS Answerer,
    NULL AS AnswererReputation,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    0 AS NumAnswers,
    0 AS TotalAnswerScore,
    0.0 AS AvgAnswerScore,
    0 AS NumAcceptedAnswers,
    0 AS NewCommentsCount,
    'No Comments' AS Commenters,
    0 AS TagCount,
    NULL AS TagHierarchy
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.Score >= 100
  AND NOT EXISTS (
    SELECT 1 FROM Posts ans WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2
  )
ORDER BY p.Score DESC
LIMIT 50;
