-- {"query": "5020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1080} 
WITH RecentUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, 
           ROW_NUMBER() OVER (ORDER BY u.CreationDate DESC) AS RowNum
    FROM Users u
    WHERE u.Reputation > 5000
),
TopQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.Score, p.CreationDate,
           p.Tags, p.ViewCount, p.AnswerCount,
           COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS ActivityScore
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (SELECT MIN(CreationDate) FROM RecentUsers WHERE RowNum <= 100)
      AND p.Score > 5
),
UserBadges AS (
    SELECT b.UserId, COUNT(DISTINCT b.Name) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '2 years'
    GROUP BY b.UserId
),
QuestionLinks AS (
    SELECT pl.PostId, COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
           COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
VoteStats AS (
    SELECT v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) AS TotalVotes
    FROM Votes v
    WHERE v.CreationDate > NOW() - INTERVAL '180 days'
    GROUP BY v.PostId
),
TagExtract AS (
    SELECT tq.Id AS PostId,
           unnest(string_to_array(substring(tq.Tags, 2, length(tq.Tags)-2), '><')) AS TagName
    FROM TopQuestions tq
    WHERE tq.Tags IS NOT NULL
)
SELECT 
    tq.Id AS QuestionId,
    tq.Title,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.ActivityScore,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COALESCE(ub.BadgeCount, 0) AS BadgesEarntRecent,
    COALESCE(ub.GoldBadges, 0) || 'G ' || COALESCE(ub.SilverBadges, 0) || 'S ' || COALESCE(ub.BronzeBadges, 0) || 'B' AS BadgeSummary,
    COALESCE(vs.UpVotes, 0) AS RecentUpVotes,
    COALESCE(vs.DownVotes, 0) AS RecentDownVotes,
    COALESCE(vs.TotalVotes, 0) AS RecentTotalVotes,
    COALESCE(ql.LinkedCount, 0) AS NumLinked,
    COALESCE(ql.DuplicateCount, 0) AS NumDuplicateLinks,
    STRING_AGG(DISTINCT te.TagName, ', ') AS TagList,
    CASE 
        WHEN tq.Score > 50 AND COALESCE(vs.UpVotes, 0) > 100 THEN 'HOT'
        WHEN tq.ViewCount > 20000 THEN 'TRENDING'
        WHEN tq.AnswerCount = 0 THEN 'UNANSWERED'
        ELSE 'NORMAL'
    END AS PopularityStatus,
    CASE 
        WHEN tq.OwnerUserId IS NULL THEN 'Community'
        ELSE 'User'
    END AS OwnerType,
    (COALESCE(tq.Score,0) * 2 + COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0) + COALESCE(ub.BadgeCount,0))::int AS PerformanceScore
FROM TopQuestions tq
LEFT JOIN Users u ON tq.OwnerUserId = u.Id
LEFT JOIN UserBadges ub ON tq.OwnerUserId = ub.UserId
LEFT JOIN VoteStats vs ON tq.Id = vs.PostId
LEFT JOIN QuestionLinks ql ON tq.Id = ql.PostId
LEFT JOIN TagExtract te ON tq.Id = te.PostId
GROUP BY tq.Id, tq.Title, tq.Score, tq.ViewCount, tq.AnswerCount, tq.ActivityScore, u.DisplayName, u.Reputation, ub.BadgeCount, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, vs.UpVotes, vs.DownVotes, vs.TotalVotes, ql.LinkedCount, ql.DuplicateCount, tq.OwnerUserId
HAVING COUNT(DISTINCT te.TagName) >= 2
ORDER BY PerformanceScore DESC, tq.CreationDate DESC
LIMIT 50;