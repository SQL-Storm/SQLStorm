WITH PostVoteCounts AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVoteCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) - SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS NetVoteScore,
        MAX(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN v.CreationDate END) AS AcceptedDate
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod', 'AcceptedByOriginator')
    GROUP BY p.Id
),
AnswerDetails AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererUserId,
        p.CreationDate AS AnswerCreationDate,
        pvc.UpVoteCount AS AnswerUpVotes,
        pvc.DownVoteCount AS AnswerDownVotes,
        pvc.NetVoteScore AS AnswerNetVoteScore,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY COALESCE(pvc.NetVoteScore, 0) DESC, pvc.AcceptedDate DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostVoteCounts pvc ON p.Id = pvc.PostId
    WHERE pt.Name = 'Answer'
),
QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Title AS QuestionTitle,
        p.Tags AS QuestionTags,
        p.AnswerCount AS TotalAnswerCount,
        pvc.UpVoteCount AS QuestionUpVotes,
        pvc.DownVoteCount AS QuestionDownVotes,
        pvc.NetVoteScore AS QuestionNetVoteScore,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostVoteCounts pvc ON p.Id = pvc.PostId
    WHERE pt.Name = 'Question'
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT q.QuestionId) AS QuestionsAsked,
        COUNT(DISTINCT a.AnswerId) AS AnswersGiven,
        SUM(a.AnswerUpVotes) AS TotalAnswerUpVotesReceived,
        SUM(a.AnswerDownVotes) AS TotalAnswerDownVotesReceived,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN QuestionDetails q ON u.Id = q.QuestionerUserId
    LEFT JOIN AnswerDetails a ON u.Id = a.AnswererUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostTagCounts AS (
    -- Split tags like '<sql><performance>' into rows: 'sql', 'performance'
    SELECT
        TRIM(tag) AS TagName,
        COUNT(*) AS TagUseCount
    FROM (
        SELECT
            p.Id,
            CASE
                WHEN tag_parts.tag = '' THEN NULL
                ELSE tag_parts.tag
            END AS tag
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT value AS tag
            FROM (
                WITH recursive_split AS (
                    SELECT
                        CASE WHEN p.Tags IS NULL THEN NULL
                             ELSE REPLACE(REPLACE(p.Tags, '><', '|'), '<', '')
                        END AS tagstr
                )
                SELECT
                    -- split tagstr by '|' using a recursive CTE
                    value
                FROM (
                    WITH RECURSIVE splitter(pos, rest) AS (
                        SELECT 1, (SELECT tagstr FROM recursive_split)
                        UNION ALL
                        SELECT
                            pos + 1,
                            CASE
                                WHEN POSITION('|' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('|' IN rest) + 1)
                                ELSE ''
                            END
                        FROM splitter
                        WHERE rest <> '' AND POSITION('|' IN rest) > 0
                    ),
                    parts AS (
                        SELECT
                            TRIM(
                                CASE
                                    WHEN POSITION('|' IN (SELECT tagstr FROM recursive_split)) = 0 THEN (SELECT tagstr FROM recursive_split)
                                    ELSE SUBSTRING((SELECT tagstr FROM recursive_split) FROM 1 FOR POSITION('|' IN (SELECT tagstr FROM recursive_split)) - 1)
                                END
                            ) AS value
                        FROM (SELECT 1) x
                        WHERE (SELECT tagstr FROM recursive_split) IS NOT NULL
                        UNION ALL
                        SELECT
                            TRIM(
                                CASE
                                    WHEN POSITION('|' IN rest) = 0 THEN rest
                                    ELSE SUBSTRING(rest FROM 1 FOR POSITION('|' IN rest) - 1)
                                END
                            )
                        FROM splitter
                        WHERE rest IS NOT NULL AND rest <> ''
                    )
                    SELECT value FROM parts WHERE value IS NOT NULL AND value <> ''
                ) s
            ) sp
        ) tag_parts
    ) derived
    WHERE tag IS NOT NULL
    GROUP BY TRIM(tag)
)
SELECT
    qd.QuestionId,
    qd.QuestionTitle,
    qd.QuestionCreationDate,
    qd.QuestionerUserId,
    COALESCE(ue.DisplayName, 'Unknown User') AS QuestionerDisplayName,
    ue.Reputation AS QuestionerReputation,
    qd.QuestionStatus,
    qd.QuestionNetVoteScore,
    ad.AnswerId AS BestAnswerId,
    ad.AnswererUserId AS BestAnswererUserId,
    COALESCE(bue.DisplayName, 'Unknown User') AS BestAnswererDisplayName,
    ad.AnswerNetVoteScore AS BestAnswerNetVoteScore,
    ad.AnswerUpVotes AS BestAnswerUpVotes,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = qd.QuestionId
          AND c.UserId IS NOT NULL
          AND c.Text LIKE '%interesting%'
    ) AS CommentCountWithInteresting,
    CASE
        WHEN qd.QuestionTags LIKE '%<sql>%' THEN 'SQL Related'
        WHEN qd.QuestionTags LIKE '%<performance>%' THEN 'Performance Related'
        ELSE 'Other'
    END AS TagCategory,
    CAST(SUBSTRING(qd.QuestionTitle FROM 1 FOR 50) AS VARCHAR(50)) AS ShortTitle,
    CASE
        WHEN qd.QuestionCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days') THEN 'Old'
        WHEN qd.QuestionCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days') THEN 'Recent'
        ELSE 'Mid-Age'
    END AS AgeGroup,
    ptc.TagUseCount AS PrimaryTagUseCount
FROM QuestionDetails qd
LEFT JOIN UserEngagement ue ON qd.QuestionerUserId = ue.UserId
LEFT JOIN AnswerDetails ad ON qd.QuestionId = ad.QuestionId AND ad.AnswerRank = 1
LEFT JOIN UserEngagement bue ON ad.AnswererUserId = bue.UserId
LEFT JOIN PostTagCounts ptc ON
    -- extract first tag between '<' and '>'
    TRIM(SUBSTRING(qd.QuestionTags FROM 2 FOR CASE WHEN POSITION('>' IN qd.QuestionTags) > 1 THEN POSITION('>' IN qd.QuestionTags) - 2 ELSE CHAR_LENGTH(qd.QuestionTags) END)) = ptc.TagName
WHERE qd.QuestionId IN (
    SELECT PostId
    FROM PostHistory
    WHERE PostHistoryTypeId = 10 AND Comment = '102'
) OR qd.QuestionId IN (
    SELECT RelatedPostId
    FROM PostLinks
    WHERE LinkTypeId = 3
)
ORDER BY qd.QuestionCreationDate DESC
LIMIT 100;