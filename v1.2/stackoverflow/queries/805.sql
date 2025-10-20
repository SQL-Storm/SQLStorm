with RecursiveUserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        coalesce(sum(v.VoteTypeScore), 0) as NetVotes,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            v.PostId,
            sum(case 
                when vt.Name = 'UpMod' then 1 
                when vt.Name = 'DownMod' then -1 
                else 0 
            end) as VoteTypeScore
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.PostId
    ) v on v.PostId = p.Id
    where u.CreationDate < cast('2024-10-01' as date) - interval '1 year' and u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
TopUsersWithBadges as (
    select
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.Location,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.NetVotes,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        rank() over (partition by rua.Location order by rua.Reputation desc, rua.NetVotes desc) as UserLocRank,
        rua.LocRank
    from RecursiveUserActivity rua
    left join Badges b on b.UserId = rua.UserId
),
UserPostDetails as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        count(*) over (partition by p.OwnerUserId, p.PostTypeId) as PostTypeCount
    from Posts p
    where p.CreationDate > cast('2024-10-01' as date) - interval '6 months'
),
LatestCommentPerPost as (
    select
        c.PostId,
        c.Id as CommentId,
        c.UserId as CommentUserId,
        c.Text as CommentText,
        c.CreationDate as CommentDate
    from (
        select *,
            row_number() over (partition by PostId order by CreationDate desc) as rn
        from Comments
    ) c
    where c.rn = 1
),
PostHistoryEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Text,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRank
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
),
PostLinksWithType as (
    select
        pl.Id,
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId as QuestionOwnerId,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.ParentId
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
DuplicateQuestions as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinksWithType pl
    join Posts p on p.Id = pl.PostId and p.PostTypeId = 1
    where pl.LinkTypeName = 'Duplicate'
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as TotalQuestions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as TotalAnswers,
        count(distinct c.Id) as TotalComments,
        coalesce(sum(vt.VoteCount), 0) as TotalVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select v.PostId, count(*) as VoteCount
        from Votes v
        group by v.PostId
    ) vt on vt.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        rank() over (partition by b.Class order by count(*) desc) as BadgeClassRank,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats AS (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        avg(case when p.PostTypeId in (1,2) then p.Score end) as AvgPostScore,
        max(case when p.PostTypeId in (1,2) then p.Score end) as MaxPostScore,
        min(case when p.PostTypeId in (1,2) then p.Score end) as MinPostScore,
        stddev_samp(case when p.PostTypeId in (1,2) then p.Score end) as StdDevPostScore
    from Users ua
    left join Posts p on p.OwnerUserId = ua.Id
    group by ua.Id, ua.DisplayName, ua.Reputation
)
select
    u.UserId as UserId,
    u.DisplayName,
    u.Location,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.NetVotes,
    coalesce(string_agg(distinct b.Name || ' (' || case when b.Class = 1 then 'Gold' when b.Class = 2 then 'Silver' else 'Bronze' end || ')', ', '), 'No Badges') as Badges,
    upd.PostId as RecentPostId,
    upd.Title as RecentPostTitle,
    coalesce(lc.CommentText, 'No recent comments') as LatestCommentOnRecentPost,
    ph.Text as LatestEditText,
    ph.CreationDate as LatestEditDate,
    dup.OriginalQuestionId,
    concat(
        'Questions: ', cast(u.QuestionCount as varchar),
        ' | Answers: ', cast(u.AnswerCount as varchar),
        ' | Votes: ', cast(u.NetVotes as varchar),
        ' | Badges: ', coalesce(cast(count(distinct b.Id) as varchar), '0')
    ) as Summary,
    uas.AvgPostScore,
    uas.MaxPostScore,
    uas.MinPostScore,
    uas.StdDevPostScore,
    ur.BadgeClassRank,
    ur.BadgeCount,
    u.LocRank,
    u.UserLocRank
from TopUsersWithBadges u
left join Badges b on b.UserId = u.UserId
left join UserPostDetails upd on upd.OwnerUserId = u.UserId and upd.RecentPostRank = 1
left join LatestCommentPerPost lc on lc.PostId = upd.PostId
left join PostHistoryEdits ph on ph.PostId = upd.PostId and ph.EditRank = 1
left join DuplicateQuestions dup on dup.DuplicateQuestionId = upd.PostId
left join UserActivitySummary ua on ua.Id = u.UserId
left join UserReputationStats uas on uas.Id = u.UserId
left join (
    select
        UserId,
        Class,
        rank() over (partition by Class order by BadgeCount desc) as BadgeClassRank,
        BadgeCount
    from (
        select UserId, Class, count(*) as BadgeCount
        from Badges
        group by UserId, Class
    ) sub
) ur on ur.UserId = u.UserId
where u.LocRank <= 3 and u.UserLocRank <= 5 and u.QuestionCount > 5
group by
    u.UserId, u.DisplayName, u.Location, u.Reputation, u.QuestionCount, u.AnswerCount, u.NetVotes,
    upd.PostId, upd.Title,
    lc.CommentText,
    ph.Text, ph.CreationDate,
    dup.OriginalQuestionId,
    uas.AvgPostScore, uas.MaxPostScore, uas.MinPostScore, uas.StdDevPostScore,
    ur.BadgeClassRank, ur.BadgeCount, u.LocRank, u.UserLocRank
order by u.Location, u.Reputation desc, u.NetVotes desc
limit 100;