WITH RepUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.GoldBadgeCount, 0)        AS GoldBadgeCount,
        COALESCE(p.QuestionCount, 0)         AS QuestionCount,
        COALESCE(v.VoteScore, 0)             AS VoteScore,
        CONCAT('User_', u.Id)                AS UserTag,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS GoldBadgeCount
        FROM Badges
        WHERE Class = 1               -- gold only
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT OwnerUserId AS UserId, COUNT(*) AS QuestionCount
        FROM Posts
        WHERE PostTypeId = 1          -- questions
        GROUP BY OwnerUserId
    ) p ON u.Id = p.UserId
    LEFT JOIN (
        SELECT 
            p.OwnerUserId AS UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                     WHEN v.VoteTypeId = 3 THEN -1
                     ELSE 0 END) AS VoteScore
        FROM Posts p
        JOIN Votes v ON p.Id = v.PostId
        GROUP BY p.OwnerUserId
    ) v ON u.Id = v.UserId
    WHERE u.Reputation > 10000
),
TagContributors AS (
    SELECT 
        t.TagName,
        u.Id                                     AS UserId,
        u.DisplayName,
        COUNT(*)                                 AS Contributions,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY COUNT(*) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, u.Id, u.DisplayName
    HAVING COUNT(*) >= 5
),
RecentEdits AS (
    SELECT 
        ph.UserId,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)      -- title/body/tags edits
    GROUP BY ph.UserId
),
CombinedSet AS (
    SELECT
        ru.Id,
        ru.DisplayName,
        ru.Reputation,
        ru.GoldBadgeCount,
        ru.QuestionCount,
        ru.VoteScore,
        ru.UserTag,
        ru.RepRank,
        CAST(NULL AS VARCHAR)      AS TagName,
        CAST(NULL AS INTEGER)      AS Contributions,
        CAST(NULL AS INTEGER)      AS TagRank,
        COALESCE(re.LastEdit, u.CreationDate) AS LastActivity
    FROM RepUsers ru
    LEFT JOIN RecentEdits re ON ru.Id = re.UserId
    LEFT JOIN Users u ON ru.Id = u.Id
    WHERE ru.RepRank <= 50

    UNION ALL

    SELECT
        tc.UserId,
        tc.DisplayName,
        u.Reputation,
        COALESCE(b.BadgeCount,0)               AS GoldBadgeCount,
        COALESCE(p.QuestionCount,0)            AS QuestionCount,
        COALESCE(v.VoteScore,0)                AS VoteScore,
        CONCAT('TagUser_', tc.UserId)          AS UserTag,
        NULL                                   AS RepRank,
        tc.TagName,
        tc.Contributions,
        tc.TagRank,
        COALESCE(re.LastEdit, u.CreationDate)  AS LastActivity
    FROM TagContributors tc
    JOIN Users u ON u.Id = tc.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT OwnerUserId AS UserId, COUNT(*) AS QuestionCount
        FROM Posts
        GROUP BY OwnerUserId
    ) p ON u.Id = p.UserId
    LEFT JOIN (
        SELECT 
            p.OwnerUserId AS UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                     WHEN v.VoteTypeId = 3 THEN -1
                     ELSE 0 END) AS VoteScore
        FROM Posts p
        JOIN Votes v ON p.Id = v.PostId
        GROUP BY p.OwnerUserId
    ) v ON u.Id = v.UserId
    LEFT JOIN RecentEdits re ON u.Id = re.UserId
    WHERE tc.TagRank <= 10
)
SELECT *
FROM (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        GoldBadgeCount,
        QuestionCount,
        VoteScore,
        UserTag,
        RepRank,
        TagName,
        Contributions,
        TagRank,
        LastActivity,
        DENSE_RANK() OVER (
            ORDER BY Reputation DESC,
                     GoldBadgeCount DESC,
                     Contributions DESC
        ) AS OverallRank,
        CASE
            WHEN Reputation IS NULL               THEN 'NoRep'
            WHEN Reputation > 50000               THEN 'UltraHigh'
            WHEN Reputation > 20000               THEN 'High'
            WHEN Reputation > 10000               THEN 'Medium'
            ELSE                                  'Low'
        END                                    AS RepBand,
        COALESCE(TagName, 'General')           AS PrimaryTag
    FROM CombinedSet
) final
WHERE OverallRank <= 100
ORDER BY OverallRank, Id
LIMIT 200;