WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
),
RankedUsersPrep AS (
    SELECT 
        UserId,
        Reputation,
        NTILE(4) OVER (ORDER BY Reputation DESC) AS ReputationQuartile,
        (QuestionCount * 3 + AnswerCount * 2 + CommentCount) AS ActivityScore,
        (UpVoteCount - DownVoteCount) AS NetVotes,
        QuestionCount,
        AnswerCount,
        CommentCount,
        UpVoteCount,
        DownVoteCount
    FROM UserActivity
),
RankedUsers AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (PARTITION BY ReputationQuartile ORDER BY ActivityScore DESC) AS ActivityRank
    FROM RankedUsersPrep r
),
ClosedPosts AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT ph.PostId) AS ClosedPostCount
    FROM Posts p
    INNER JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY p.OwnerUserId
),
UserTags AS (
    SELECT 
        u.Id AS UserId,
        STRING_AGG(tag, ', ' ORDER BY tag_count DESC, tag) AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN LATERAL (
        SELECT 
            tag,
            COUNT(*) AS tag_count
        FROM (
            SELECT TRIM(BOTH '<>' FROM value) AS tag
            FROM (
                -- split tags stored like "<tag1><tag2>"
                -- handle empty Tags safely
                SELECT CASE WHEN COALESCE(p.Tags, '') = '' THEN NULL ELSE p.Tags END AS tags_blob
            ) pb,
            UNNEST(
                CASE WHEN pb.tags_blob IS NULL THEN ARRAY[]::VARCHAR[] 
                     ELSE regexp_split_to_array(pb.tags_blob, '><') END
            ) AS value
        ) t
        WHERE tag IS NOT NULL AND tag <> ''
        GROUP BY tag
    ) tags ON TRUE
    GROUP BY u.Id
)
SELECT 
    ru.UserId,
    ru.ReputationQuartile,
    ru.ActivityRank,
    ru.ActivityScore,
    ru.NetVotes,
    COALESCE(cp.ClosedPostCount, 0) AS ClosedPostCount,
    ut.TopTags,
    CASE 
        WHEN u.WebsiteUrl IS NOT NULL AND u.Location IS NOT NULL THEN 'Full Profile'
        WHEN u.WebsiteUrl IS NULL AND u.Location IS NULL THEN 'Minimal Profile'
        ELSE 'Partial Profile' 
    END AS ProfileStatus,
    COALESCE((
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ru.UserId)
          AND pl.LinkTypeId = 3
    ), 0) AS DuplicateLinks,
    ru.Reputation
FROM RankedUsers ru
LEFT JOIN ClosedPosts cp ON ru.UserId = cp.UserId
LEFT JOIN UserTags ut ON ru.UserId = ut.UserId
LEFT JOIN Users u ON ru.UserId = u.Id
WHERE ru.Reputation > 1000
GROUP BY
    ru.UserId,
    ru.ReputationQuartile,
    ru.ActivityRank,
    ru.ActivityScore,
    ru.NetVotes,
    cp.ClosedPostCount,
    ut.TopTags,
    u.WebsiteUrl,
    u.Location,
    ru.Reputation
ORDER BY 
    ru.ReputationQuartile, 
    ru.ActivityScore DESC, 
    ru.NetVotes DESC;