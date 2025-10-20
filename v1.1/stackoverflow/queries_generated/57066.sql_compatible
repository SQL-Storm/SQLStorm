WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(v.Id) AS VoteCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
        MAX(p.LastActivityDate) AS LastActivity
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        VoteCount,
        UpVoteCount,
        DownVoteCount,
        LastActivity
    FROM
        ActiveUsers
    WHERE
        Reputation >= 1000
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViewCount
    FROM
        Tags t
    JOIN
        Posts p ON t.TagName = ANY(
            regexp_split_to_array(
                -- remove leading '<' and trailing '>' if present, then split on '><'
                CASE
                    WHEN p.Tags LIKE '<%>' THEN
                        SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2)
                    ELSE
                        p.Tags
                END,
                '><'
            )
        )
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.Id, t.TagName, t.Count
    ORDER BY
        TagCount DESC
    LIMIT 10
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.LastActivityDate
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days'
),
HighActivityPosts AS (
    SELECT
        rp.PostId,
        rp.PostTypeId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.LastActivityDate,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount
    FROM
        RecentPosts rp
    LEFT JOIN
        Comments c ON rp.PostId = c.PostId
    LEFT JOIN
        Votes v ON rp.PostId = v.PostId
    GROUP BY
        rp.PostId, rp.PostTypeId, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerUserId, rp.OwnerDisplayName, rp.LastActivityDate
    ORDER BY
        VoteCount DESC, CommentCount DESC
    LIMIT 10
)
SELECT
    hr.UserId,
    hr.Reputation,
    hr.PostCount,
    hr.QuestionCount,
    hr.AnswerCount,
    hr.VoteCount,
    hr.UpVoteCount,
    hr.DownVoteCount,
    hr.LastActivity,
    tt.TagName,
    tt.TagCount,
    tt.QuestionCount AS TagQuestionCount,
    tt.AvgScore AS TagAvgScore,
    tt.TotalViewCount AS TagTotalViewCount,
    hap.PostId,
    hap.PostTypeId,
    hap.CreationDate,
    hap.Score AS PostScore,
    hap.ViewCount AS PostViewCount,
    hap.OwnerUserId AS PostOwnerUserId,
    hap.OwnerDisplayName AS PostOwnerDisplayName,
    hap.LastActivityDate AS PostLastActivityDate,
    hap.CommentCount,
    hap.VoteCount AS PostVoteCount
FROM
    HighReputationUsers hr
CROSS JOIN
    TopTags tt
LEFT JOIN
    HighActivityPosts hap ON hr.UserId = hap.OwnerUserId
WHERE
    hr.LastActivity >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days'
GROUP BY
    hr.UserId,
    hr.Reputation,
    hr.PostCount,
    hr.QuestionCount,
    hr.AnswerCount,
    hr.VoteCount,
    hr.UpVoteCount,
    hr.DownVoteCount,
    hr.LastActivity,
    tt.TagName,
    tt.TagCount,
    tt.QuestionCount,
    tt.AvgScore,
    tt.TotalViewCount,
    hap.PostId,
    hap.PostTypeId,
    hap.CreationDate,
    hap.Score,
    hap.ViewCount,
    hap.OwnerUserId,
    hap.OwnerDisplayName,
    hap.LastActivityDate,
    hap.CommentCount,
    hap.VoteCount
ORDER BY
    hr.Reputation DESC, tt.TagCount DESC, hap.VoteCount DESC;