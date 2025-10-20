-- {"query": "4035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1098} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- questions and answers only
      AND p.CreationDate >= '2020-01-01' -- recent posts
),
TagExploded AS (
    SELECT
        rp.Id AS PostId,
        unnest(string_to_array(trim(BOTH '<>' FROM rp.Tags), '><')) AS Tag
    FROM RankedPosts rp
    WHERE rp.Tags IS NOT NULL
),
TagCounts AS (
    SELECT
        Tag,
        COUNT(DISTINCT PostId) AS PostCount,
        AVG((SELECT Score FROM Posts WHERE Id = rp.PostId)) AS AvgScore
    FROM TagExploded rp
    GROUP BY Tag
),
PostWithComments AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        c.CommentCount,
        c.LastCommentDate,
        c.TopCommentUserId,
        c.TopCommentText
    FROM RankedPosts p
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount,
            MAX(CreationDate) AS LastCommentDate,
            MAX(UserId) FILTER (WHERE Score = max_score) AS TopCommentUserId,
            MAX(Text) FILTER (WHERE Score = max_score) AS TopCommentText
        FROM (
            SELECT
                PostId,
                UserId,
                Text,
                Score,
                RANK() OVER (PARTITION BY PostId ORDER BY Score DESC NULLS LAST) AS rk,
                MAX(Score) OVER (PARTITION BY PostId) AS max_score,
                CreationDate
            FROM Comments
        ) sub
        WHERE rk = 1
        GROUP BY PostId
    ) c ON p.Id = c.PostId
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
PopularQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PopularRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%<sql>%'
      AND p.Score > 10
      AND p.ViewCount > 1000
)
SELECT
    pq.Id AS QuestionId,
    pq.Title,
    pq.Score,
    pq.ViewCount,
    pq.Tags,
    u.DisplayName AS QuestionOwnerName,
    bs.BadgeCount,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    pc.CommentCount,
    pc.LastCommentDate,
    cuser.DisplayName AS TopCommentUserName,
    pc.TopCommentText,
    tc.PostCount AS TagPopularity,
    tc.AvgScore AS TagAverageScore,
    EXISTS (
        SELECT 1 FROM PostLinks pl
        WHERE pl.PostId = pq.Id
          AND pl.LinkTypeId = 3 -- duplicate links
          AND pl.RelatedPostId IN (
              SELECT Id FROM Posts WHERE Score > pq.Score
          )
    ) AS HasHigherScoringDuplicate,
    CASE
        WHEN pq.Score >= 100 THEN 'High'
        WHEN pq.Score >= 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreCategory,
    ROW_NUMBER() OVER (ORDER BY pq.Score DESC) AS GlobalRank
FROM PopularQuestions pq
LEFT JOIN Users u ON pq.OwnerUserId = u.Id
LEFT JOIN UserBadgeStats bs ON u.Id = bs.UserId
LEFT JOIN PostWithComments pc ON pq.Id = pc.Id
LEFT JOIN Users cuser ON pc.TopCommentUserId = cuser.Id
LEFT JOIN LATERAL (
    SELECT
        tc.PostCount,
        tc.AvgScore
    FROM TagCounts tc
    WHERE tc.Tag = (SELECT unnest(string_to_array(trim(BOTH '<>' FROM pq.Tags), '><')) LIMIT 1)
    LIMIT 1
) tc ON true
WHERE bs.BadgeCount IS NOT NULL
ORDER BY pq.Score DESC, pq.ViewCount DESC
LIMIT 50;