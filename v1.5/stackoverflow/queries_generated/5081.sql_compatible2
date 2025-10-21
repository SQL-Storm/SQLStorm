WITH TopActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        u.CreationDate > (SELECT MIN(CreationDate) FROM Users) + INTERVAL '1' YEAR
        AND u.Reputation > 500
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    HAVING
        COUNT(p.Id) > 5
),
UserVotesAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM
        Votes v
        INNER JOIN Posts p ON v.PostId = p.Id
    GROUP BY
        p.OwnerUserId
),
TagPerformance AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) AS HighScoringPosts,
        MAX(p.ViewCount) AS MaxViews
    FROM
        Tags t
        INNER JOIN Posts p ON
            (p.PostTypeId IN (1,2))
            AND p.Tags IS NOT NULL
            AND POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
    GROUP BY
        t.TagName
    HAVING
        COUNT(DISTINCT p.Id) > 50 AND SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) > 5
),
CommentAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(LENGTH(c.Text)) AS MaxCommentLength
    FROM
        Comments c
        INNER JOIN Posts p ON c.PostId = p.Id
    GROUP BY
        p.OwnerUserId
),
PostCloseAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.ClosedDate IS NOT NULL) AS ClosedPostCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseEventCount,
        MAX(ph.CreationDate) AS LastClosedDate,
        SUM(CASE WHEN cr.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateCloses,
        SUM(CASE WHEN cr.Name = 'Off-topic' THEN 1 ELSE 0 END) AS OffTopicCloses
    FROM
        Posts p
        LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
        LEFT JOIN CloseReasonTypes cr ON NULLIF(ph.Comment, '') = CAST(cr.Id AS VARCHAR)
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    t.UserId,
    t.DisplayName,
    t.Reputation,
    t.TotalPosts,
    t.QuestionCount,
    t.AnswerCount,
    t.BadgeCount,
    t.TotalViews,
    t.LastPostDate,
    uv.UpvotesReceived,
    uv.DownvotesReceived,
    ca.CommentCount,
    ca.AvgCommentScore,
    ca.MaxCommentLength,
    pa.ClosedPostCount,
    pa.CloseEventCount,
    pa.LastClosedDate,
    pa.DuplicateCloses,
    pa.OffTopicCloses,
    (
        SELECT STRING_AGG(tp.TagName, ', ')
        FROM TagPerformance tp
        WHERE tp.TagName IN (
            SELECT DISTINCT SUBSTRING(t2.TagName FROM 1 FOR 20)
            FROM Posts p2
            JOIN Tags t2 ON p2.Tags IS NOT NULL
                AND POSITION(CONCAT('<', t2.TagName, '>') IN p2.Tags) > 0
            WHERE p2.OwnerUserId = t.UserId
        )
    ) AS PopularTags,
    RANK() OVER (
        ORDER BY t.TotalPosts DESC, t.Reputation DESC
    ) AS ActivityRank,
    COALESCE(uv.UpvotesReceived, 0) * 1.0 / NULLIF(t.TotalPosts, 0) AS AvgPostUpvotes,
    CASE
        WHEN ca.CommentCount IS NULL THEN 'NO_COMMENTS'
        WHEN ca.CommentCount > 50 THEN 'HEAVY_COMMENTER'
        ELSE 'SOME_COMMENTS'
    END AS CommentProfile
FROM
    TopActiveUsers t
    LEFT JOIN UserVotesAgg uv ON t.UserId = uv.UserId
    LEFT JOIN CommentAgg ca ON t.UserId = ca.UserId
    LEFT JOIN PostCloseAgg pa ON t.UserId = pa.UserId
ORDER BY
    ActivityRank
LIMIT 50;