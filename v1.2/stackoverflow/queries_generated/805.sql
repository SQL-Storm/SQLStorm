-- {"query": "805.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1838} 
with RecursiveUserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        coalesce(sum(v.VoteTypeScore), 0) as NetVotes,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
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
    ) v on v.PostId = p.Id or v.PostId = p2.Id
    where u.CreationDate < current_date - interval '1 year' and u.Reputation > 1000
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
        rank() over (partition by rua.Location order by rua.Reputation desc, rua.NetVotes desc) as UserLocRank
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
    where p.CreationDate > current_date - interval '6 months'
),
LatestCommentPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.UserId as CommentUserId,
        c.Text as CommentText,
        c.CreationDate as CommentDate
    from Comments c
    order by c.PostId, c.CreationDate desc
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
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
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
    select distinct q.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinksWithType pl
    join Posts q on q.Id = pl.PostId and q.PostTypeId = 1
    where pl.LinkTypeName = 'Duplicate'
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as TotalQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as TotalAnswers,
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
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        min(p.Score) filter (where p.PostTypeId in (1,2)) as MinPostScore,
        stddev_samp(p.Score) filter (where p.PostTypeId in (1,2)) as StdDevPostScore
    from Users ua
    left join Posts p on p.OwnerUserId = ua.Id
    group by ua.Id, ua.DisplayName, ua.Reputation
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Location,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.NetVotes,
    coalesce(string_agg(distinct b.Name || ' (' || case b.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', '), 'No Badges') as Badges,
    upd.PostId as RecentPostId,
    upd.Title as RecentPostTitle,
    coalesce(lc.CommentText, 'No recent comments') as LatestCommentOnRecentPost,
    ph.Text as LatestEditText,
    ph.CreationDate as LatestEditDate,
    dup.OriginalQuestionId,
    concat_ws(' | ',
        'Questions: ' || u.QuestionCount,
        'Answers: ' || u.AnswerCount,
        'Votes: ' || u.NetVotes,
        'Badges: ' || coalesce(count(distinct b.Id)::text, '0')
    ) as Summary,
    ua.AvgPostScore,
    ua.MaxPostScore,
    ua.MinPostScore,
    ua.StdDevPostScore,
    ur.BadgeClassRank,
    ur.BadgeCount
from TopUsersWithBadges u
left join Badges b on b.UserId = u.UserId
left join UserPostDetails upd on upd.OwnerUserId = u.UserId and upd.RecentPostRank = 1
left join LatestCommentPerPost lc on lc.PostId = upd.PostId
left join PostHistoryEdits ph on ph.PostId = upd.PostId and ph.EditRank = 1
left join DuplicateQuestions dup on dup.DuplicateQuestionId = upd.PostId
left join UserActivitySummary ua on ua.Id = u.UserId
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
order by u.Location, u.Reputation desc, u.NetVotes desc
limit 100;