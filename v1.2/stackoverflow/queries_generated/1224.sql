-- {"query": "1224.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1275} 
with RecursiveUserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(b.Id) as BadgeCount,
        row_number() over(partition by u.Id order by b.Class) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.Class
), LatestPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentRank
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
), UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as QuestionsCount,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as AnswersCount,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        count(distinct ph.PostId) as EditsMade
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id and ph.PostId = p.Id
    group by u.Id, u.DisplayName
), CloseReasonsCount as (
    select
        ph.UserId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.UserId, crt.Name
), CombinedStats as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.MaxQuestionScore,
        ua.MaxAnswerScore,
        ua.EditsMade,
        coalesce(rc.CloseCount,0) as CloseVotesCast,
        string_agg(distinct crt.Name, ', ') within group (order by crt.Name) as CloseReasons,
        rbs.Class as BadgeClass,
        rbs.BadgeCount,
        rs.RecentPostsTitles
    from UserActivity ua
    left join CloseReasonsCount rc on rc.UserId = ua.UserId
    left join PostHistory ph on ph.UserId = ua.UserId
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    left join RecursiveUserBadgeStats rbs on rbs.UserId = ua.UserId and rbs.BadgeRank = 1
    left join (
        select 
            p.OwnerUserId,
            string_agg(p.Title, ' | ' order by p.CreationDate desc) as RecentPostsTitles
        from LatestPosts p 
        where p.RecentRank <= 3
        group by p.OwnerUserId
    ) rs on rs.OwnerUserId = ua.UserId
    group by 
        ua.UserId, ua.DisplayName, ua.QuestionsCount, ua.AnswersCount, ua.MaxQuestionScore, ua.MaxAnswerScore, ua.EditsMade, 
        rc.CloseCount, rbs.Class, rbs.BadgeCount, rs.RecentPostsTitles
), AnswerUpvoteRatio as (
    select
        p.OwnerUserId as UserId,
        count(v.Id) filter (where vt.Name = 'UpMod') as UpVotesOnAnswers,
        count(v.Id) filter (where vt.Name = 'DownMod') as DownVotesOnAnswers,
        case 
            when count(v.Id) filter (where vt.Name = 'DownMod') = 0 then
                count(v.Id) filter (where vt.Name = 'UpMod')
            else 
                (count(v.Id) filter (where vt.Name = 'UpMod'))::float / (count(v.Id) filter (where vt.Name = 'DownMod'))
        end as UpDownRatio
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    where p.PostTypeId = 2 
    group by p.OwnerUserId
)
select
    cs.UserId,
    coalesce(cs.DisplayName, '<anonymous>') as UserName,
    cs.Reputation,
    cs.QuestionsCount,
    cs.AnswersCount,
    cs.MaxQuestionScore,
    cs.MaxAnswerScore,
    cs.EditsMade,
    cs.CloseVotesCast,
    coalesce(cs.CloseReasons, 'None') as CloseReasonsVoted,
    cs.BadgeClass,
    cs.BadgeCount,
    cs.RecentPostsTitles,
    coalesce(aur.UpVotesOnAnswers,0) as UpVotesOnAnswers,
    coalesce(aur.DownVotesOnAnswers,0) as DownVotesOnAnswers,
    round(coalesce(aur.UpDownRatio,0),2) as UpVoteToDownVoteRatio,
    length(cs.RecentPostsTitles) - length(replace(cs.RecentPostsTitles, ' ', '')) + 1 as RecentPostWordCount,
    case when cs.Reputation > 100000 then 'Elite' when cs.Reputation > 10000 then 'High Rep' when cs.Reputation > 1000 then 'Intermediate' else 'New or Low Rep' end as ReputationClass
from CombinedStats cs
left join AnswerUpvoteRatio aur on aur.UserId = cs.UserId
join Users u on u.Id = cs.UserId
order by cs.Reputation desc NULLS LAST, cs.AnswersCount desc NULLS LAST, cs.MaxAnswerScore desc NULLS LAST
limit 100;