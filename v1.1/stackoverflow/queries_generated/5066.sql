-- {"query": "5066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1130} 
WITH RecentActiveQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CURRENT_DATE - INTERVAL '90 days')
),
TopCommenters AS (
    SELECT
        c.UserId,
        COUNT(*) AS CommentCount,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS CommentRank
    FROM Comments c
    WHERE c.CreationDate > (CURRENT_DATE - INTERVAL '90 days')
      AND c.UserId IS NOT NULL
    GROUP BY c.UserId
),
ActiveBadgeUsers AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MIN(b.Date) AS FirstBadge,
        MAX(b.Date) AS LastBadge
    FROM Badges b
    WHERE b.Date > (CURRENT_DATE - INTERVAL '90 days')
    GROUP BY b.UserId
),
VoteStats AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
ClosedReasons AS (
    SELECT
        ph.PostId,
        cr.Name AS CloseReason,
        ph.CreationDate AS ClosedAt
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes cr ON
        ph.Comment = CAST(cr.Id AS varchar)
    WHERE ph.PostHistoryTypeId = 10
),
TagParse AS (
    SELECT
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
    FROM RecentActiveQuestions q
    WHERE q.Tags IS NOT NULL
    LIMIT 10000
),
TaggedStats AS (
    SELECT
        tp.TagName,
        COUNT(DISTINCT tp.QuestionId) AS QuestionCount
    FROM TagParse tp
    GROUP BY tp.TagName
),
LinkedQuestions AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS NumLinked,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS NumDuplicates
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    COALESCE(vs.UpVotes, 0) AS UpVotes,
    COALESCE(vs.DownVotes, 0) AS DownVotes,
    COALESCE(vs.Favorites, 0) AS Favorites,
    lq.NumLinked,
    lq.NumDuplicates,
    CASE 
        WHEN cr.CloseReason IS NOT NULL THEN cr.CloseReason
        ELSE 'Open' 
    END AS CloseReason,
    cr.ClosedAt,
    u.Reputation,
    u.Location,
    acu.BadgeCount,
    acu.GoldBadges,
    COALESCE(tc.CommentCount,0) AS RecentCommentCount,
    array_agg(DISTINCT tps.TagName) FILTER (WHERE tps.TagName IS NOT NULL) AS Tags,
    sum(ts.QuestionCount) OVER (ORDER BY q.rn ROWS BETWEEN CURRENT ROW AND 9 FOLLOWING) AS TagMomentum10,
    SUM(q.Score) OVER () AS TotalScore
FROM RecentActiveQuestions q
LEFT JOIN VoteStats vs ON q.QuestionId = vs.PostId
LEFT JOIN ClosedReasons cr ON q.QuestionId = cr.PostId
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN ActiveBadgeUsers acu ON q.OwnerUserId = acu.UserId
LEFT JOIN TopCommenters tc ON q.OwnerUserId = tc.UserId AND tc.CommentRank <= 20
LEFT JOIN LinkedQuestions lq ON q.QuestionId = lq.PostId
LEFT JOIN TagParse tps ON q.QuestionId = tps.QuestionId
LEFT JOIN TaggedStats ts ON tps.TagName = ts.TagName
GROUP BY
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    vs.UpVotes,
    vs.DownVotes,
    vs.Favorites,
    lq.NumLinked,
    lq.NumDuplicates,
    cr.CloseReason,
    cr.ClosedAt,
    u.Reputation,
    u.Location,
    acu.BadgeCount,
    acu.GoldBadges,
    tc.CommentCount,
    q.rn
ORDER BY
    q.rn
LIMIT 50;