WITH
UserStats AS (
    SELECT
        u.Id                                          AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id)                                     AS BadgeCount,
        (SELECT SUM(
                 CASE b.Class
                      WHEN 1 THEN 100
                      WHEN 2 THEN  50
                      ELSE   10
                 END)
         FROM Badges b
         WHERE b.UserId = u.Id)                                                                  AS BadgeScore,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)           AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2)           AS AnswerCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id
                                      AND p.PostTypeId = 2
                                      AND p.Id = p.AcceptedAnswerId)                            AS AcceptedAnswerCount
    FROM Users u
),

TagInfo AS (
    SELECT
        t.Id            AS TagId,
        t.TagName,
        t.Count         AS TagUseCount,
        CASE WHEN t.IsModeratorOnly IS NULL THEN 0 ELSE CAST(t.IsModeratorOnly AS INTEGER) END AS IsModOnly,
        CASE WHEN t.IsRequired IS NULL THEN 0 ELSE CAST(t.IsRequired AS INTEGER) END           AS IsRequired,
        COALESCE(LENGTH(e.Body),0)    AS ExcerptLength,
        COALESCE(LENGTH(w.Body),0)    AS WikiLength
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),

PostAggregates AS (
    SELECT
        p.Id                     AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.Tags,
        COALESCE(v.UpVotes,0)    AS UpVoteCount,
        COALESCE(v.DownVotes,0)  AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.Score DESC, p.CreationDate DESC) AS OwnerPostRank
    FROM Posts p
    LEFT JOIN (
        SELECT
            Vote.PostId,
            SUM(CASE WHEN Vote.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN Vote.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes Vote
        GROUP BY Vote.PostId
    ) v ON v.PostId = p.Id
    WHERE p.PostTypeId IN (1,2)
),

RecentActivity AS (
    SELECT
        u.Id                                            AS UserId,
        MAX(p.CreationDate)                            AS LastPostDate,
        MAX(v.CreationDate)                            AS LastVoteDate,
        MAX(c.CreationDate)                            AS LastCommentDate,
        CASE
            WHEN MAX(p.CreationDate) IS NULL THEN NULL
            ELSE DATE_PART('day', CAST('2024-10-01 12:34:56' AS TIMESTAMP) - MAX(p.CreationDate))
        END                                            AS DaysSinceLastPost
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes    v ON v.UserId       = u.Id
    LEFT JOIN Comments c ON c.UserId       = u.Id
    GROUP BY u.Id
),

CombinedUsers AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.BadgeCount,
        us.BadgeScore,
        us.QuestionCount,
        us.AnswerCount,
        us.AcceptedAnswerCount,
        ra.DaysSinceLastPost,
        ROW_NUMBER() OVER (ORDER BY
            (us.Reputation      * 0.40) +
            (us.BadgeScore      * 0.30) +
            (us.NetVotes        * 0.20) +
            (us.AnswerCount     * 0.10) DESC)                     AS OverallRank,
        STRING_AGG(DISTINCT t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS TopTags
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.UserId = us.UserId
    LEFT JOIN Posts p           ON p.OwnerUserId = us.UserId
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
    ) pt ON TRUE
    LEFT JOIN Tags t            ON t.TagName = pt.Tag
    GROUP BY us.UserId, us.DisplayName, us.Reputation, us.NetVotes,
             us.BadgeCount, us.BadgeScore,
             us.QuestionCount, us.AnswerCount, us.AcceptedAnswerCount,
             ra.DaysSinceLastPost
)

SELECT
    UserId,
    DisplayName,
    Reputation,
    NetVotes,
    BadgeCount,
    BadgeScore,
    QuestionCount,
    AnswerCount,
    AcceptedAnswerCount,
    DaysSinceLastPost,
    OverallRank,
    TopTags
FROM CombinedUsers
WHERE OverallRank <= 100

UNION ALL

SELECT
    CAST(NULL AS INTEGER)              AS UserId,
    t.TagName                          AS DisplayName,
    CAST(NULL AS INTEGER)              AS Reputation,
    CAST(NULL AS INTEGER)              AS NetVotes,
    CAST(NULL AS INTEGER)              AS BadgeCount,
    CAST(NULL AS INTEGER)              AS BadgeScore,
    CAST(NULL AS INTEGER)              AS QuestionCount,
    CAST(NULL AS INTEGER)              AS AnswerCount,
    CAST(NULL AS INTEGER)              AS AcceptedAnswerCount,
    CAST(NULL AS INTEGER)              AS DaysSinceLastPost,
    ROW_NUMBER() OVER (ORDER BY t.TagUseCount DESC) AS OverallRank,
    CAST(NULL AS VARCHAR)              AS TopTags
FROM TagInfo t
WHERE t.TagUseCount > 5000
ORDER BY OverallRank
LIMIT 150;