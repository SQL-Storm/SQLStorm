WITH RankedPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.UserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
      AND ph.PostHistoryTypeId IN (2, 5)
),
RecentEdits AS (
    SELECT
        rph.PostId,
        rph.UserId AS EditorUserId,
        rph.CreationDate AS EditDate,
        CASE
            WHEN rph.PostTypeId = 1 THEN 'Question'
            WHEN rph.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        rph.PostTypeId,
        rph.OwnerUserId,
        ROW_NUMBER() OVER(PARTITION BY rph.PostId ORDER BY rph.CreationDate DESC) AS edit_rn
    FROM RankedPostHistory rph
    WHERE rph.rn = 1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesCount,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostContent AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.ClosedDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN EXTRACT(EPOCH FROM (p.LastActivityDate - p.ClosedDate)) / 86400
            ELSE NULL
        END AS DaysOpen,
        LENGTH(REGEXP_REPLACE(p.Body, '<[^>]*>', '', 'g')) AS BodyCharCount,
        p.LastActivityDate,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AllEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5)
)
SELECT
    pc.PostId,
    pc.Title,
    pc.Tags,
    pc.Score AS PostScore,
    pc.AnswerCount,
    pc.CommentCount,
    pc.CreationDate AS PostCreationDate,
    pc.ClosedDate,
    pc.DaysOpen,
    pc.BodyCharCount,
    re.EditorUserId,
    re.EditDate AS LastEditDate,
    re.PostType,
    ua_editor.DisplayName AS EditorDisplayName,
    ua_editor.Reputation AS EditorReputation,
    ua_owner.DisplayName AS OwnerDisplayName,
    ua_owner.Reputation AS OwnerReputation,
    COALESCE(ae.TotalVotes, 0) AS EditorTotalVotes,
    COALESCE(ae.UpVotesCount, 0) AS EditorUpVotes,
    COALESCE(ae.DownVotesCount, 0) AS EditorDownVotes,
    COALESCE(ae.TotalBadges, 0) AS EditorTotalBadges,
    (EXTRACT(EPOCH FROM (pc.CreationDate - re.EditDate)) / 3600) AS TimeDifference,
    CASE WHEN pc.Title LIKE '%?%' THEN 'HasQuestionMark' ELSE 'NoQuestionMark' END AS TitleQuestionMarkStatus,
    LENGTH(pc.Tags) AS TagLength
FROM PostContent pc
LEFT JOIN RecentEdits re ON pc.PostId = re.PostId AND re.edit_rn = 1
LEFT JOIN UserActivity ua_editor ON re.EditorUserId = ua_editor.UserId
LEFT JOIN Users u_owner ON pc.OwnerUserId = u_owner.Id
LEFT JOIN UserActivity ua_owner ON u_owner.Id = ua_owner.UserId
LEFT JOIN (
    SELECT
        Votes.UserId AS UserId,
        COUNT(*) AS TotalVotes,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
        COUNT(*) AS TotalBadges
    FROM Votes
    JOIN Users ON Votes.UserId = Users.Id
    GROUP BY Votes.UserId
) AS ae ON re.EditorUserId = ae.UserId
LEFT JOIN (
    SELECT
        UserId,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
) AS ab ON re.EditorUserId = ab.UserId
WHERE pc.Score > 10
  AND pc.AnswerCount > 0
  AND ua_editor.Reputation > 1000
  AND (re.EditDate IS NULL OR re.EditDate > TIMESTAMP '2023-01-01')
GROUP BY
    pc.PostId,
    pc.Title,
    pc.Tags,
    pc.Score,
    pc.AnswerCount,
    pc.CommentCount,
    pc.CreationDate,
    pc.ClosedDate,
    pc.DaysOpen,
    pc.BodyCharCount,
    re.EditorUserId,
    re.EditDate,
    re.PostType,
    ua_editor.DisplayName,
    ua_editor.Reputation,
    ua_owner.DisplayName,
    ua_owner.Reputation,
    ae.TotalVotes,
    ae.UpVotesCount,
    ae.DownVotesCount,
    ae.TotalBadges,
    pc.LastActivityDate
ORDER BY pc.Score DESC, pc.LastActivityDate DESC
LIMIT 100;