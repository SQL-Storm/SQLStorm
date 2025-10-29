-- {"query": "2318.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1452}
WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate AS PostCreationDate,
        bh.PostHistoryTypeId,
        bh.CreationDate AS HistoryChangeDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY bh.CreationDate DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory bh ON bh.PostId = p.Id
    WHERE u.Reputation > 1000
),
FilteredUserActivity AS (
    SELECT *
    FROM RecursiveUserActivity
    WHERE rn = 1
),
UserBadgeRanks AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class) AS BadgeCountByClass,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    JOIN Users u ON u.Id = b.UserId
    WHERE b.Date >= (CAST('2024-10-01' AS DATE) - INTERVAL '365 days')
),
LatestUserBadges AS (
    SELECT UserId, Name, Class, BadgeCountByClass
    FROM UserBadgeRanks
    WHERE rn <= 3
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
ComplexQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        q.CreationDate,
        q.OwnerUserId,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(a.TotalUpVotes, 0) AS TotalAnswerUpVotes,
        COALESCE(a.TotalDownVotes, 0) AS TotalAnswerDownVotes,
        (SELECT STRING_AGG(distinct tag, ', ')
         FROM (
             SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM q.Tags), '><') AS tag
         ) t
        ) AS TagList,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN AnswerStats a ON a.QuestionId = q.Id
    WHERE q.PostTypeId = 1
      AND q.Score >= 5
      AND q.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
      AND q.Tags IS NOT NULL
    GROUP BY
      q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.Tags, q.CreationDate, q.OwnerUserId, u.DisplayName, u.Reputation, a.AvgAnswerScore, a.MaxAnswerScore, a.TotalUpVotes, a.TotalDownVotes, q.ClosedDate
),
TagPopularity AS (
    SELECT
        tag AS Tag,
        COUNT(*) AS QuestionCount,
        AVG(Score) AS AvgScore,
        SUM(ViewCount) AS TotalViews
    FROM (
        SELECT
            UNNEST(regexp_split_to_array(TRIM(BOTH '<>' FROM Tags), '><')) AS tag,
            Score,
            ViewCount
        FROM Posts
        WHERE PostTypeId = 1
          AND Tags IS NOT NULL
    ) t
    GROUP BY tag
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        u.DisplayName,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.Score) AS MaxCommentScore
    FROM Comments c
    LEFT JOIN Users u ON u.Id = c.UserId
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId, u.DisplayName
),
HighEngagementUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ua.CommentCount,
        COALESCE(ua.AvgCommentScore, 0) AS AvgCommentScore,
        COALESCE(ua.MaxCommentScore, 0) AS MaxCommentScore,
        b.Class AS TopBadgeClass,
        b.Name AS TopBadgeName
    FROM Users u
    LEFT JOIN UserCommentActivity ua ON ua.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, Name, Class, ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Class ASC, Date DESC) AS rn
        FROM Badges
    ) b ON b.UserId = u.Id AND b.rn = 1
    WHERE u.Reputation > 5000
)
SELECT
    cq.QuestionId,
    cq.Title,
    cq.OwnerName,
    cq.OwnerReputation,
    cq.Score,
    cq.ViewCount,
    cq.AnswerCount,
    cq.AvgAnswerScore,
    cq.MaxAnswerScore,
    cq.TotalAnswerUpVotes,
    cq.TotalAnswerDownVotes,
    cq.IsClosed,
    cq.TagList,
    tp.QuestionCount AS TagQuestionCount,
    tp.AvgScore AS TagAvgScore,
    tp.TotalViews AS TagTotalViews,
    heu.DisplayName AS TopCommenterName,
    heu.Reputation AS TopCommenterReputation,
    heu.CommentCount AS TopCommenterCommentCount,
    heu.AvgCommentScore AS TopCommenterAvgCommentScore,
    heu.MaxCommentScore AS TopCommenterMaxCommentScore,
    heu.TopBadgeClass AS TopCommenterBadgeClass,
    heu.TopBadgeName AS TopCommenterBadgeName,
    lub.Name AS RecentBadgeName,
    lub.Class AS RecentBadgeClass,
    lub.BadgeCountByClass AS RecentBadgeCount
FROM ComplexQuestions cq
LEFT JOIN LATERAL (
    SELECT tp.*
    FROM TagPopularity tp
    WHERE tp.Tag = (SELECT (regexp_split_to_table(cq.TagList, ', ')) LIMIT 1)
    LIMIT 1
) tp ON TRUE
LEFT JOIN LATERAL (
    SELECT UserId
    FROM Comments
    WHERE PostId = cq.QuestionId AND UserId IS NOT NULL
    GROUP BY UserId
    ORDER BY COUNT(*) DESC
    LIMIT 1
) topc ON TRUE
LEFT JOIN HighEngagementUsers heu ON heu.Id = topc.UserId
LEFT JOIN LatestUserBadges lub ON lub.UserId = cq.OwnerUserId
WHERE cq.IsClosed = 0
  AND EXISTS (
    SELECT 1
    FROM Votes v2
    WHERE v2.PostId = cq.QuestionId
      AND v2.VoteTypeId = 2
      AND v2.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '90 days')
)
ORDER BY cq.Score DESC, cq.ViewCount DESC
LIMIT 50;