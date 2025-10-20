-- {"query": "2071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 644} 

WITH PopularTags AS (
    SELECT TagName, ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(Score, 0)) DESC) AS Rank
    FROM Posts
    JOIN (
        SELECT UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><')) AS TagName, Id
        FROM Posts
        WHERE PostTypeId = 1
        AND Tags IS NOT NULL
    ) AS TagList ON Posts.Id = TagList.Id
    WHERE CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY TagName
),
BestAnswers AS (
    SELECT ParentId, PostId, MAX(Score) AS BestScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId, PostId
    HAVING MAX(Score) > 5
),
RecentBadges AS (
    SELECT UserId, Name, COUNT(*) AS BadgeCount
    FROM Badges
    WHERE Date > NOW() - INTERVAL '1 month'
    GROUP BY UserId, Name
),
EnrichedUsers AS (
    SELECT Users.Id AS UserId, DisplayName, Reputation, COALESCE(SUM(Votes.VoteTypeId = 2)::int - SUM(Votes.VoteTypeId = 3)::int, 0) AS NetVotes
    FROM Users
    LEFT JOIN Votes ON Users.Id = Votes.UserId
    GROUP BY Users.Id, DisplayName, Reputation
),
UserWithRecentActivity AS (
    SELECT DISTINCT UserId
    FROM Posts
    WHERE CreationDate > NOW() - INTERVAL '2 week'
    UNION
    SELECT DISTINCT UserId
    FROM Comments
    WHERE CreationDate > NOW() - INTERVAL '2 week'
)
SELECT
    U.DisplayName,
    U.Reputation,
    COALESCE(P.Score, 0) AS LastPostScore,
    COALESCE(RB.BadgeCount, 0) AS RecentBadgesCount,
    ET.NetVotes,
    COALESCE(PT.Rank, 'N/A') AS TagRank
FROM Users U
LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.CreationDate = (
    SELECT MAX(CreationDate)
    FROM Posts P2
    WHERE P2.OwnerUserId = U.Id
)
LEFT JOIN RecentBadges RB ON U.Id = RB.UserId
LEFT JOIN EnrichedUsers ET ON U.Id = ET.UserId
LEFT JOIN UserWithRecentActivity UA ON U.Id = UA.UserId
LEFT JOIN PopularTags PT ON EXISTS (
    SELECT 1
    FROM Posts
    WHERE OwnerUserId = U.Id AND Tags IS NOT NULL AND PT.TagName = ANY(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><'))
)
WHERE U.LastAccessDate > NOW() - INTERVAL '3 month'
AND COALESCE(BestAnswers.BestScore, 0) > 10
ORDER BY U.Reputation DESC, LastPostScore DESC, RecentBadgesCount DESC;
