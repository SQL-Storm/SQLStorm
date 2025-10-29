-- {"query": "3430.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2293} 

WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        COALESCE(AVG(p.Score),0) AS AvgPostScore,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')      AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')    AS DownVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'Favorite')   AS FavoritesGiven,
        MAX(v.CreationDate)                            AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
UserTagAffinity AS (
    SELECT
        us.UserId,
        tt.TagName,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (5,6)) AS EditCount,
        ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (5,6)) DESC) AS TagAffinityRank
    FROM UserStats us
    JOIN Posts p ON p.OwnerUserId = us.UserId AND p.PostTypeId = 1
    JOIN LATERAL regexp_split_to_table(p.Tags, '><') AS tag_raw ON TRUE
    JOIN Tags tt ON tt.TagName = replace(replace(tag_raw, '<', ''), '>', '')
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (5,6)
    GROUP BY us.UserId, tt.TagName
),
LatestPostPerUser AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TotalPostScore,
    us.AvgPostScore,
    us.QuestionCount,
    us.AnswerCount,
    us.LastPostDate,
    rv.UpVotesGiven,
    rv.DownVotesGiven,
    rv.FavoritesGiven,
    rv.LastVoteDate,
    lp.Title AS LatestPostTitle,
    lp.CreationDate AS LatestPostDate,
    COALESCE(uta.TagName, 'None') AS TopTagByEdits,
    COALESCE(uta.EditCount,0)    AS EditsOnTopTag,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation BETWEEN 5000 AND 20000 THEN 'Pro'
        WHEN us.Reputation BETWEEN 1000 AND 4999 THEN 'Active'
        ELSE 'Newbie'
    END AS ReputationBand,
    CASE 
        WHEN us.AnswerCount = 0 THEN NULL
        ELSE ROUND(1.0 * us.QuestionCount / us.AnswerCount, 2)
    END AS QtoARatio,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostLinks pl
            WHERE pl.PostId = lp.PostId AND pl.LinkTypeId = 3
        ) THEN 1 ELSE 0 END AS IsDuplicateLinked
FROM UserStats us
LEFT JOIN RecentVotes rv      ON rv.UserId = us.UserId
LEFT JOIN LatestPostPerUser lp ON lp.UserId = us.UserId AND lp.rn = 1
LEFT JOIN UserTagAffinity uta ON uta.UserId = us.UserId AND uta.TagAffinityRank = 1
WHERE us.Reputation > 1000
ORDER BY us.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
