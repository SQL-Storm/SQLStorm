-- {"query": "324.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1154} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date is not null
),
TopBadges as (
    select UserId, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionAnswerStats as (
    select
        p.OwnerUserId,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
        avg(case when p.PostTypeId = 1 then p.Score end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score end) as AvgAnswerScore,
        max(p.CreationDate) as LastPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        qu.QuestionCount,
        qu.AnswerCount,
        qu.AvgQuestionScore,
        qu.AvgAnswerScore,
        qu.LastPostDate,
        count(distinct ph.PostId) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenEvents,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
        row_number() over (order by u.Reputation desc, qu.QuestionCount desc nulls last) as UserRank
    from Users u
    left join QuestionAnswerStats qu on u.Id = qu.OwnerUserId
    left join PostHistory ph on ph.UserId = u.Id and ph.CreationDate >= u.CreationDate and ph.CreationDate <= u.LastAccessDate
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, qu.QuestionCount, qu.AnswerCount, qu.AvgQuestionScore, qu.AvgAnswerScore, qu.LastPostDate
),
DuplicateQuestions as (
    select distinct p.Id as QuestionId, pl.RelatedPostId as DuplicateOfId
    from Posts p
    inner join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    where p.PostTypeId = 1
),
UserDuplicateCounts as (
    select
        p.OwnerUserId,
        count(distinct dq.QuestionId) as DuplicateQuestionCount
    from Posts p
    left join DuplicateQuestions dq on p.Id = dq.QuestionId
    where p.PostTypeId = 1
    group by p.OwnerUserId
),
FinalUserStats as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgQuestionScore,
        ua.AvgAnswerScore,
        ua.CloseReopenEvents,
        ua.CommentCount,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        coalesce(udc.DuplicateQuestionCount, 0) as DuplicateQuestionCount,
        string_agg(distinct tb.BadgeName || ' (' || case tb.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', ') as TopBadgesList
    from UserActivityWindow ua
    left join UserDuplicateCounts udc on ua.Id = udc.OwnerUserId
    left join TopBadges tb on ua.Id = tb.UserId
    group by ua.Id, ua.DisplayName, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.AvgQuestionScore, ua.AvgAnswerScore, ua.CloseReopenEvents, ua.CommentCount, ua.UpVotesReceived, ua.DownVotesReceived, udc.DuplicateQuestionCount
)
select
    fus.Id as UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.QuestionCount,
    fus.AnswerCount,
    round(fus.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    round(fus.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    fus.CloseReopenEvents,
    fus.CommentCount,
    fus.UpVotesReceived,
    fus.DownVotesReceived,
    fus.DuplicateQuestionCount,
    fus.TopBadgesList,
    case
        when fus.DuplicateQuestionCount > 5 then 'High Duplicate Rate'
        when fus.CloseReopenEvents > 10 then 'Highly Active in Moderation'
        when fus.Reputation > 10000 then 'High Reputation User'
        else 'Regular User'
    end as UserCategory
from FinalUserStats fus
where fus.QuestionCount > 0 or fus.AnswerCount > 0
order by fus.Reputation desc nulls last, fus.QuestionCount desc nulls last
limit 100;