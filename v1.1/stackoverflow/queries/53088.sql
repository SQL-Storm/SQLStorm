WITH PopularTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS QuestionCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM 
        Tags t
    WHERE 
        t.Count > 1000
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.BountyAmount) AS TotalBountiesEarned
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    WHERE 
        u.Reputation > 10000
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = true THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
-- compute time differences per user first, then aggregate without embedding window inside aggregate
EditIntervals AS (
    SELECT
        ph.UserId,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate))) AS IntervalSeconds
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6,7,8,9)
),
EditFrequency AS (
    SELECT
        ei.UserId,
        COUNT(*) FILTER (WHERE ei.IntervalSeconds IS NOT NULL) + 1 AS TotalEdits, -- +1 to account for first row as an edit
        AVG(ei.IntervalSeconds) AS AvgTimeBetweenEditsSeconds
    FROM
        EditIntervals ei
    GROUP BY
        ei.UserId
    HAVING
        (COUNT(*) FILTER (WHERE ei.IntervalSeconds IS NOT NULL) + 1) > 10
),
CommentEngagement AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    WHERE 
        c.Score > 0
    GROUP BY 
        c.UserId
),
UserTagContributions AS (
    SELECT 
        u.Id AS UserId,
        pt.TagId,
        COUNT(DISTINCT p.Id) AS PostsInTag,
        SUM(p.Score) AS TotalScoreInTag
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name
    JOIN 
        PopularTags pt ON pt.TagName = tag_name
    WHERE 
        p.PostTypeId IN (1, 2)
    GROUP BY 
        u.Id, pt.TagId
    HAVING 
        SUM(p.Score) > 100
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.TotalPosts,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.AvgPostScore,
    ua.TotalBountiesEarned,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.TagBasedBadges,
    ef.TotalEdits,
    ef.AvgTimeBetweenEditsSeconds,
    ce.TotalComments,
    ce.AvgCommentScore,
    STRING_AGG(CONCAT(pt.TagName, ': ', utc.PostsInTag, ' posts, score ', utc.TotalScoreInTag), '; ') AS TagContributions
FROM 
    UserActivity ua
LEFT JOIN 
    BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN 
    EditFrequency ef ON ua.UserId = ef.UserId
LEFT JOIN 
    CommentEngagement ce ON ua.UserId = ce.UserId
LEFT JOIN 
    UserTagContributions utc ON ua.UserId = utc.UserId
LEFT JOIN 
    PopularTags pt ON utc.TagId = pt.TagId
WHERE 
    ua.Reputation > 50000
    AND (bs.GoldBadges > 5 OR ef.TotalEdits > 100)
GROUP BY 
    ua.UserId, ua.Reputation, ua.TotalPosts, ua.QuestionsPosted, ua.AnswersPosted, ua.AvgPostScore, ua.TotalBountiesEarned,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, bs.TagBasedBadges,
    ef.TotalEdits, ef.AvgTimeBetweenEditsSeconds,
    ce.TotalComments, ce.AvgCommentScore
ORDER BY 
    ua.Reputation DESC, ua.TotalPosts DESC
LIMIT 100;