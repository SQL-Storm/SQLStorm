-- {"query": "972.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1502} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(p.Score, 0) AS TagScore,
        p.CreationDate AS TagFirstPostDate,
        p.OwnerUserId
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        th.Id,
        th.TagName,
        th.Count,
        th.TagScore + COALESCE(p.Score, 0),
        LEAST(th.TagFirstPostDate, p.CreationDate),
        th.OwnerUserId
    FROM RecursiveTagHierarchy th
    JOIN Posts p ON p.Tags LIKE '%' || th.TagName || '%'
    WHERE p.PostTypeId = 1
    AND p.CreationDate > th.TagFirstPostDate
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COALESCE(SUM(v.VoteTypeId = 2)::int, 0) AS TotalUpVotesReceived,
        COALESCE(SUM(v.VoteTypeId = 3)::int, 0) AS TotalDownVotesReceived,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(b.Id) AS BadgesCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopQuestionsWithAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        u.DisplayName AS Answerer,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
      AND q.Score >= (
          SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1
      )
),
DuplicateQuestions AS (
    SELECT
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId,
        p1.Title AS DuplicateTitle,
        p2.Title AS OriginalTitle,
        pl.CreationDate AS LinkCreationDate
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId AND p1.PostTypeId = 1
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId AND p2.PostTypeId = 1
    WHERE pl.LinkTypeId = 3
),
UserBadgesLatest AS (
    SELECT DISTINCT ON (UserId, Name)
        UserId,
        Name,
        Date AS AwardedDate,
        Class,
        TagBased
    FROM Badges
    ORDER BY UserId, Name, Date DESC
),
WindowedUserReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('year', u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRank
    FROM Users u
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.TotalUpVotesReceived,
    ua.TotalDownVotesReceived,
    ua.AvgPostScore,
    ua.LastPostDate,
    ua.BadgesCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    twq.QuestionId,
    twq.Title AS TopQuestionTitle,
    twq.QuestionScore,
    twq.ViewCount,
    twq.AnswerCount,
    twq.AnswerId,
    twq.AnswerScore,
    twq.AnswerCreationDate,
    twq.Answerer,
    dq.DuplicateQuestionId,
    dq.OriginalQuestionId,
    dq.DuplicateTitle,
    dq.OriginalTitle,
    dq.LinkCreationDate,
    ubl.Name AS LatestBadgeName,
    ubl.Class AS LatestBadgeClass,
    ubl.AwardedDate AS LatestBadgeAwardedDate,
    wh.ReputationRank,
    wh.YearlyRank,
    CASE WHEN ua.TotalUpVotesReceived + ua.TotalDownVotesReceived = 0 THEN NULL
         ELSE ROUND(CAST(ua.TotalUpVotesReceived AS numeric) / NULLIF(ua.TotalUpVotesReceived + ua.TotalDownVotesReceived,0), 4)
    END AS UpVoteRatio,
    CONCAT_WS(' - ', ua.DisplayName, COALESCE(NULLIF(ua.Location, ''), 'Unknown Location')) AS UserDisplayAndLocation,
    STRING_AGG(DISTINCT rt.TagName, ', ') AS UserTopTags
FROM UserActivitySummary ua
LEFT JOIN TopQuestionsWithAnswerStats twq ON twq.Answerer = ua.DisplayName AND twq.AnswerRank = 1
LEFT JOIN DuplicateQuestions dq ON dq.DuplicateQuestionId IN (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
)
LEFT JOIN UserBadgesLatest ubl ON ubl.UserId = ua.UserId
LEFT JOIN WindowedUserReputation wh ON wh.Id = ua.UserId
LEFT JOIN LATERAL (
    SELECT rt.TagName
    FROM RecursiveTagHierarchy rt
    JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.Tags LIKE '%' || rt.TagName || '%'
    GROUP BY rt.TagName
    ORDER BY SUM(p.Score) DESC
    LIMIT 5
) rt ON TRUE
WHERE ua.QuestionsAsked > 2
  AND (ua.GoldBadges > 0 OR ua.SilverBadges > 5)
ORDER BY wh.ReputationRank, ua.BadgesCount DESC
LIMIT 100;
