WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.Reputation
),
TagStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        STRING_AGG(t.TagName, ', ') AS TopTags,
        COUNT(DISTINCT t.Id) AS UniqueTagsUsed
    FROM 
        Posts p
    JOIN LATERAL (
        -- split tags like '<tag1><tag2>' into rows, standard SQL using recursive or JSON functions varies by dialect.
        -- Here use a generic method: replace angle brackets and split by '><' via a simple recursive CTE.
        SELECT value
        FROM (
            SELECT 
                trim(both '<>' FROM p.Tags) AS tags_trimmed
        ) AS s
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(s.tags_trimmed, '><') AS value
        ) AS split_vals
    ) AS tag_split ON true
    JOIN 
        Tags t ON t.TagName = tag_split.value
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.OwnerUserId
),
VoteStats AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
        SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBounty
    FROM 
        Votes v
    GROUP BY 
        v.UserId
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.UserId
),
PostHistoryStats AS (
    SELECT 
        ph.UserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditsMade,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    WHERE 
        ph.UserId IS NOT NULL
    GROUP BY 
        ph.UserId
)
SELECT
    us.UserId,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgPostScore,
    us.LatestPostDate,
    us.TotalBadges,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ts.TopTags,
    ts.UniqueTagsUsed,
    vs.UpVotesGiven,
    vs.DownVotesGiven,
    vs.TotalBounty,
    cs.CommentCount,
    cs.AvgCommentScore,
    phs.EditsMade,
    phs.LastEditDate,
    RANK() OVER (ORDER BY us.GoldBadges DESC, us.Reputation DESC) AS Rank
FROM 
    UserStats us
LEFT JOIN 
    TagStats ts ON us.UserId = ts.UserId
LEFT JOIN 
    VoteStats vs ON us.UserId = vs.UserId
LEFT JOIN 
    CommentStats cs ON us.UserId = cs.UserId
LEFT JOIN 
    PostHistoryStats phs ON us.UserId = phs.UserId
WHERE 
    us.Reputation > 1000
    AND us.GoldBadges >= 1
ORDER BY 
    Rank
LIMIT 100;