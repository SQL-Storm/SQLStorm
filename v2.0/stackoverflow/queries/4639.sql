WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankByReputation,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS AccessRank,
        u.CreationDate,
        u.LastAccessDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> ''
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostVoteAnalysis AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostTypeName,
        p.Title,
        p.CreationDate AS PostCreationDate,
        v.VoteTypeId,
        vt.Name AS VoteTypeName,
        u.Id AS VoterUserId,
        u.DisplayName AS VoterDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY v.CreationDate DESC) AS VoteSequence,
        CASE
            WHEN vt.Name = 'UpMod' THEN 1
            WHEN vt.Name = 'DownMod' THEN -1
            ELSE 0
        END AS VoteValue
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Users u ON v.UserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
AggregatedPostVotes AS (
    SELECT
        PostId,
        PostTypeName,
        Title,
        PostCreationDate,
        SUM(VoteValue) AS NetVoteScore,
        COUNT(CASE WHEN VoteTypeName = 'UpMod' THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN VoteTypeName = 'DownMod' THEN 1 END) AS DownVoteCount,
        MAX(CASE WHEN VoteSequence = 1 THEN VoterDisplayName ELSE NULL END) AS LastVoterDisplayName,
        MAX(CASE WHEN VoteSequence = 1 THEN VoteTypeName ELSE NULL END) AS LastVoteType
    FROM PostVoteAnalysis
    GROUP BY PostId, PostTypeName, Title, PostCreationDate
),
TopPostPerOwner AS (
    SELECT p.Id AS PostId, p.OwnerUserId
    FROM Posts p
    JOIN AggregatedPostVotes apv ON p.Id = apv.PostId
    ORDER BY apv.NetVoteScore DESC, apv.UpVoteCount DESC
    FETCH FIRST 1 ROWS ONLY
)
SELECT
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.PostCount,
    r.QuestionCount,
    r.AnswerCount,
    r.CommentCount,
    r.RankByReputation,
    CAST(NULL AS INTEGER) AS DisplayNameLevenshtein,
    CASE WHEN r.AccessRank = 1 THEN 'Most Recent' ELSE 'Older' END AS AccessStatus,
    apv.Title AS MostVotedPostTitle,
    apv.NetVoteScore,
    apv.UpVoteCount,
    apv.DownVoteCount,
    apv.LastVoterDisplayName,
    apv.LastVoteType,
    CASE
        WHEN apv.NetVoteScore > 1000 AND r.Reputation > 50000 THEN 'Highly Engaged Power User'
        WHEN apv.NetVoteScore < -100 AND r.Reputation < 1000 THEN 'Potentially Controversial Newcomer'
        ELSE 'Standard User'
    END AS UserActivityCategory
FROM RankedUserActivity r
LEFT JOIN TopPostPerOwner tpo ON r.UserId = tpo.OwnerUserId
LEFT JOIN AggregatedPostVotes apv ON tpo.PostId = apv.PostId
WHERE r.RankByReputation BETWEEN 10 AND 20
ORDER BY r.RankByReputation, apv.NetVoteScore DESC;