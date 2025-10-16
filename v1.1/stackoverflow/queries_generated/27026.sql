-- {"query": "27026.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1692} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.LastAccessDate,
        ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY u.Reputation DESC) AS ReputationRank
    FROM
        Users u
    WHERE
        u.LastAccessDate > NOW() - INTERVAL '30 days'
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        DisplayName,
        LastAccessDate
    FROM
        ActiveUsers
    WHERE
        ReputationRank <= 100
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeName
    FROM
        Posts p
    WHERE
        p.CreationDate > NOW() - INTERVAL '7 days'
),
HighEngagementPosts AS (
    SELECT
        PostId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        Title,
        Tags,
        PostTypeName
    FROM
        RecentPosts
    WHERE
        Score > 5 OR ViewCount > 100
),
PopularTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        STRING_AGG(p.Title, ', ') AS RelatedTitles
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.ExcerptPostId = p.Id
    GROUP BY
        t.Id, t.TagName, t.Count
    ORDER BY
        t.Count DESC
    LIMIT 10
),
UserVotes AS (
    SELECT
        v.UserId,
        COUNT(v.PostId) AS TotalVotes,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM
        Votes v
    GROUP BY
        v.UserId
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS TotalAnswers
    FROM
        Posts p
    GROUP BY
        p.OwnerUserId
),
UserActivity AS (
    SELECT
        u.UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(uv.TotalVotes, 0) AS TotalVotes,
        COALESCE(uv.UpVotes, 0) AS UpVotes,
        COALESCE(uv.DownVotes, 0) AS DownVotes,
        COALESCE(ub.TotalBadges, 0) AS TotalBadges,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(ups.TotalAnswers, 0) AS TotalAnswers
    FROM
        HighReputationUsers u
    LEFT JOIN
        UserVotes uv ON u.UserId = uv.UserId
    LEFT JOIN
        UserBadges ub ON u.UserId = ub.UserId
    LEFT JOIN
        UserPostStats ups ON u.UserId = ups.OwnerUserId
),
HighEngagementPostDetails AS (
    SELECT
        p.PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.PostTypeName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        strftime('%Y-%m-%d %H:%M:%S', p.LastActivityDate) AS LastActivityDateString
    FROM
        HighEngagementPosts p
)
SELECT
    ua.UserId,
    ua.Reputation,
    ua.DisplayName,
    ua.TotalVotes,
    ua.UpVotes,
    ua.DownVotes,
    ua.TotalBadges,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    hepd.PostId,
    hepd.PostTypeId,
    hepd.CreationDate,
    hepd.Score,
    hepd.ViewCount,
    hepd.OwnerUserId,
    hepd.Title,
    hepd.Tags,
    hepd.PostTypeName,
    hepd.AnswerCount,
    hepd.CommentCount,
    hepd.LastActivityDateString,
    pt.Name AS PopularTagName,
    pt.Count AS PopularTagCount,
    pt.RelatedTitles
FROM
    UserActivity ua
    JOIN
        HighEngagementPostDetails hepd ON hepd.OwnerUserId = ua.UserId
    LEFT JOIN
        PopularTags pt ON INSTR(hepd.Tags, pt.TagName) > 0
ORDER BY
    ua.Reputation DESC,
    hepd.Score DESC,
    hepd.ViewCount DESC;
