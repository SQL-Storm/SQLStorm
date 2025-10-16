WITH PostsCombined AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.Title,
        (SELECT COUNT(*) 
         FROM Posts a 
         WHERE a.ParentId = p.Id 
           AND a.PostTypeId = 2) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),

PostVotes AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
),

TagExtract AS (
    SELECT
        pc.Id          AS PostId,
        TRIM(value)    AS TagName
    FROM PostsCombined pc
    JOIN LATERAL (
        SELECT value
        FROM UNNEST(
            string_to_array(
                replace(replace(coalesce(pc.Tags, ''), '<', ''), '>', ''),
                ' '
            )
        ) AS t(value)
    ) AS s ON true
),

TopTagPosts AS (
    SELECT
        te.TagName,
        te.PostId,
        pc.Score,
        ROW_NUMBER() OVER (PARTITION BY te.TagName ORDER BY pc.Score DESC) AS TagRank
    FROM TagExtract te
    JOIN PostsCombined pc ON pc.Id = te.PostId
    WHERE pc.PostTypeId = 1
),

UserAgg AS (
    SELECT
        u.Id            AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS UserQ,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS UserA,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UserUp,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS UserDown,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN PostsCombined p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 20
),

FinalSet AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UserQ,
        ua.UserA,
        ua.UserUp,
        ua.UserDown,
        ua.RepRank,
        tt.TagName,
        tt.TagRank,
        pc.Score,
        tt.PostId
    FROM UserAgg ua
    LEFT JOIN (
        SELECT
            UserId,
            TagName,
            TagRank,
            PostId
        FROM (
            SELECT
                t.TagName,
                t.TagRank,
                p.OwnerUserId AS UserId,
                t.PostId
            FROM TopTagPosts t
            JOIN PostsCombined p ON p.Id = t.PostId
            WHERE t.TagRank <= 3
        ) AS TopTagsForUsers
    ) AS tt ON tt.UserId = ua.UserId
    LEFT JOIN PostsCombined pc ON pc.Id = tt.PostId
),

SetCombine AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserQ,
        UserA,
        UserUp,
        UserDown,
        RepRank,
        TagName,
        TagRank,
        Score
    FROM FinalSet

    UNION ALL

    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UserQ,
        ua.UserA,
        ua.UserUp,
        ua.UserDown,
        ua.RepRank,
        'All'        AS TagName,
        0            AS TagRank,
        pc.Score
    FROM UserAgg ua
    JOIN PostsCombined pc ON pc.OwnerUserId = ua.UserId
    WHERE pc.PostTypeId = 1
)

SELECT *
FROM SetCombine
ORDER BY Reputation DESC, TagRank ASC;