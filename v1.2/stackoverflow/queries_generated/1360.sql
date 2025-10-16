-- {"query": "1360.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1870} 
with Recursive BadgeRankings as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date asc) as BadgeRank
    from Badges b
    where b.Class <= 2
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        avg(coalesce(p.Score,0)) as AvgPostScore,
        max(p.CreationDate) as LastPostDate,
        count(distinct case when p.AcceptedAnswerId is not null then p.Id end) as QuestionsWithAcceptedAnswers
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        up.TotalPosts,
        up.QuestionsCount,
        up.AnswersCount,
        up.AvgPostScore,
        up.LastPostDate,
        up.QuestionsWithAcceptedAnswers
    from Users u
    left join UserPostStats up on up.UserId = u.Id
    where u.Reputation > 10000
),
EligiblePostsWithVotes as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        vt.Name as PostTypeName,
        v_count.UpVotes,
        v_count.DownVotes,
        p.AcceptedAnswerId
    from Posts p
    left join PostTypes vt on vt.Id = p.PostTypeId
    left join (
        select
            PostId,
            sum(case when vt2.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt2.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v2
        inner join VoteTypes vt2 on vt2.Id = v2.VoteTypeId
        group by PostId
    ) v_count on v_count.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
MarkRejectedDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        case when lt.Name = 'Duplicate' then 1 else 0 end as IsDuplicateLink
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
),
QuestionAnswerHierarchy as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        a.CreationDate as AnswerCreationDate,
        ralick.BetaRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join (
      select
          bsub.UserId,
          bsub.Name,
          bsub.Class,
          row_number() over (partition by bsub.UserId order by bsub.Date asc) as BetaRank
      from Badges bsub
      where bsub.Name ilike '%beta%'
    ) raligned on raligned.UserId = a.OwnerUserId
    where q.PostTypeId = 1
),
CloseStats as (
    select
        ph.PostId,
        count(distinct case when ph.PostHistoryTypeId = 10 then ph.Id end) as CloseVotesCount,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastCloseVoteDate,
        count(distinct case when ph.PostHistoryTypeId = 11 then ph.Id end) as ReopenVotesCount
    from PostHistory ph
    group by ph.PostId
),
UserQualityMetrics as (
    select
        u.Id as UserId,
        coalesce(u.Reputation, 0) as Reputation,
        coalesce(up.TotalPosts,0) as TotalPosts,
        coalesce(pClosed.CloseVotesCount, 0) as UserPostsClosed,
        coalesce(qah.AnswerCount, 0) as AnswersGiven,
        round(coalesce(avg(coalesce(p.Score,0)) over (partition by p.OwnerUserId), 0)::numeric,2) as AvgUserPostScore,
        sum(
            case 
                when p.PostTypeId = 2 and
                p.CreationDate between u.CreationDate and u.CreationDate + interval '30 days' 
                then 1 else 0
            end
        ) as AnswersInFirst30d
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserPostStats up on up.UserId = u.Id
    left join CloseStats pClosed on pClosed.PostId = p.Id
    left join (
        select OwnerUserId, count(*) as AnswerCount from Posts where PostTypeId = 2 group by OwnerUserId
    ) qah on qah.OwnerUserId = u.Id
    group by u.Id, u.Reputation, up.TotalPosts, pClosed.CloseVotesCount, qah.AnswerCount
)
select distinct
    tu.Id as UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionsCount,
    tu.AnswersCount,
    tu.AvgPostScore,
    l578.UpVotes,
    l578.DownVotes,
    cs.CloseVotesCount,
    cs.ReopenVotesCount,
    p.Ancient_Days,
    case 
       when p.Average_Score_perDay > 5 then 'High Engagement'
       when p.Average_Score_perDay between 2 and 5 then 'Moderate Engagement'
       else 'Low Engagement'
    end as EngagementCategory,
    stus.UserPostsClosed,
    stus.AnswersGiven,
    stus.AvgUserPostScore,
    stus.AnswersInFirst30d,
    phVotes.ThirtyDayVoteGrowthRunRate,
    case when stus.UserPostsClosed > 10 then 'Flagged Contributor' else 'Regular Contributor' end as UserStatus,
    CONCAT(
        upper(left(tu.DisplayName, 1)), 
        lower(substring(tu.DisplayName from 2 for 100))
    ) as FormattedUserName,
    array_to_string(array_agg(distinct b.RankedBadgeName order by b.BatchRank asc), ',') as BadgeNamesSummary
from TopUsers tu
left join EligiblePostsWithVotes l578 on l578.OwnerUserId = tu.Id
left join CloseStats cs on cs.PostId = l578.PostId
left join (
    select
        phv.OwnerUserId,
        sum(case when vt.Name='UpMod' then 1 else 0 end) * 1.0 / nullif(max(date_part('day',current_date - phv.StartDate))::float,0) as ThirtyDayVoteGrowthRunRate
    from Votes v inner join VoteTypes vt on vt.Id = v.VoteTypeId
    inner join (
        select OwnerUserId, min(CreationDate)::date as StartDate from Posts group by OwnerUserId
    ) phv on phv.OwnerUserId = v.UserId
    group by phv.OwnerUserId
) phVotes on phVotes.OwnerUserId = tu.Id
left join UserQualityMetrics stus on stus.UserId = tu.Id
left join Lateral (
    select 
        vp.PostId,
        vp.OwnerUserId,
        max(age(current_date, vp.CreationDate)) as Ancient_Days,
        (sum(vp.Score) filter (where vp.CreationDate >= current_date - interval '30 day'))/30.0 as Average_Score_perDay
    from Posts vp 
    where vp.OwnerUserId = tu.Id
    group by vp.PostId, vp.OwnerUserId
    order by Ancient_Days desc
    limit 1
) p on true
left join Lateral (
    select
        bsub.UserId,
        string_agg(bsub.Name, '; ') as RankedBadgeName,
        row_number() over (partition by bsub.UserId order by bsub.Date desc) as BatchRank
    from Badges bsub
    where bsub.UserId = tu.Id and bsub.Class = 1
    group by bsub.UserId
) b on b.UserId = tu.Id
order by 
    tu.Reputation desc,
    tu.TotalPosts desc
limit 100;