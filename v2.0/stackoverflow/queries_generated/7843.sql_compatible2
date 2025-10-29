WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CAST('2010-01-01' AS timestamp)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserActivityAnalysis AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalScore,
        ups.LastPostDate,
        ups.AllTags,
        CASE WHEN ups.TotalPosts > 0 THEN CAST(ups.TotalScore AS numeric) / ups.TotalPosts ELSE 0 END AS AvgScorePerPost,
        CASE 
            WHEN ups.Reputation >= 10000 THEN 'Gold'
            WHEN ups.Reputation >= 2500 THEN 'Silver' 
            ELSE 'Bronze'
        END AS ReputationTier,
        COALESCE((
            SELECT COUNT(*) 
            FROM Badges b 
            WHERE b.UserId = ups.UserId 
            AND b.Date >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        ), 0) AS RecentBadgesCount,
        COALESCE((
            SELECT COUNT(*) 
            FROM Comments c 
            WHERE c.UserId = ups.UserId 
            AND c.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        ), 0) AS RecentCommentsCount
    FROM UserPostStats ups
    WHERE ups.TotalPosts >= 5
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COALESCE(p.ParentId, p.Id) AS EffectiveParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        p.Score,
        CASE 
            WHEN p.Score >= 100 THEN 'Hot'
            WHEN p.Score >= 25 THEN 'Popular'
            WHEN p.Score >= 0 THEN 'Average'
            ELSE 'Low'
        END AS Popularity,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(p.OwnerUserId, -1) AS AuthorId,
        COALESCE(u.DisplayName, 'Anonymous') AS AuthorName,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND EXISTS (
                SELECT 1 FROM Posts p2 
                WHERE p2.ParentId = p.Id AND p2.PostTypeId = 1 AND p2.ClosedDate IS NOT NULL
            ) THEN 1
            ELSE 0
        END AS IsClosed,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id),
            0
        ) AS HistoryCount,
        COALESCE(
            (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8),
            0
        ) AS TotalBounty,
        CASE 
            WHEN p.Tags IS NOT NULL THEN 
                STRING_AGG(
                    SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2)
                    , ', '
                ) 
            ELSE NULL 
        END AS TagsList
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
    AND p.PostTypeId IN (1, 2)
    AND p.ViewCount > 50
    GROUP BY p.Id, p.Title, COALESCE(p.ParentId, p.Id), p.PostTypeId, p.Score, p.CreationDate, p.ViewCount, p.AnswerCount, p.CommentCount, COALESCE(p.OwnerUserId, -1), COALESCE(u.DisplayName, 'Anonymous'), p.AcceptedAnswerId, p.ClosedDate, p.Tags
),
RankedPosts AS (
    SELECT 
        cpa.*,
        ROW_NUMBER() OVER (
            PARTITION BY PostType 
            ORDER BY Score DESC, CreationDate DESC
        ) AS ScoreRank,
        DENSE_RANK() OVER (
            ORDER BY ViewCount DESC, Score DESC
        ) AS ViewScoreRank,
        NTILE(4) OVER (ORDER BY Score) AS ScoreQuartile
    FROM ComplexPostAnalysis cpa
),
UserTagRelationships AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalTagScore,
        AVG(p.Score) AS AvgTagScore,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRanking
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    INNER JOIN (
        SELECT TagName 
        FROM Tags 
        WHERE Count >= 500
    ) t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
    GROUP BY u.Id, u.DisplayName, t.TagName
)
SELECT 
    COALESCE(ups.DisplayName, 'Anonymous User') AS UserName,
    ups.ReputationTier,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgScorePerPost,
    ups.RecentBadgesCount,
    ups.RecentCommentsCount,
    STRING_AGG(
        CASE 
            WHEN rpo.ScoreRank <= 3 
            THEN rpo.Title || ' (' || CAST(rpo.Score AS VARCHAR(10)) || ')'
            ELSE NULL 
        END, 
        '; '
    ) AS TopScoringPosts,
    STRING_AGG(
        CASE 
            WHEN rpo.ViewScoreRank <= 3 
            THEN rpo.Title || ' (' || CAST(rpo.ViewCount AS VARCHAR(10)) || ')'
            ELSE NULL 
        END, 
        '; '
    ) AS TopViewedPosts,
    STRING_AGG(
        CASE 
            WHEN rpo.ScoreQuartile = 4 
            THEN rpo.Title || ' (Hot)'
            ELSE NULL 
        END, 
        '; '
    ) AS HighScoringPosts,
    STRING_AGG(
        utr.TagName || ' (' || CAST(utr.PostCount AS VARCHAR(10)) || ' posts)',
        ', '
    ) AS TopTags,
    COUNT(DISTINCT CASE WHEN rpo.HasAcceptedAnswer = 1 THEN rpo.PostId END) AS AcceptedAnswersCount,
    COUNT(DISTINCT CASE WHEN rpo.IsClosed = 1 THEN rpo.PostId END) AS ClosedPostsCount,
    MAX(CASE WHEN rpo.TotalBounty > 0 THEN rpo.TotalBounty ELSE 0 END) AS MaxBounty,
    COUNT(DISTINCT rpo.AuthorId) AS DiverseAuthors,
    AVG(CASE WHEN rpo.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreRatio
FROM UserActivityAnalysis ups
LEFT JOIN RankedPosts rpo ON ups.UserId = rpo.AuthorId
LEFT JOIN UserTagRelationships utr ON ups.UserId = utr.UserId
WHERE ups.TotalPosts >= 10
GROUP BY ups.UserId, ups.DisplayName, ups.ReputationTier, ups.TotalPosts, ups.QuestionCount, ups.AnswerCount, ups.AvgScorePerPost, ups.RecentBadgesCount, ups.RecentCommentsCount
HAVING COUNT(DISTINCT rpo.PostId) > 0
ORDER BY ups.AvgScorePerPost DESC, ups.TotalPosts DESC;