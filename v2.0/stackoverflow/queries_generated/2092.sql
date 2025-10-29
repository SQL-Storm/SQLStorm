-- {"query": "2092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1362} 
with RecursiveVotes as (
    select 
        v.Id as VoteId,
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        1 as Level
    from Votes v
    where v.VoteTypeId in (2,3)
    union all
    select 
        v2.Id,
        v2.PostId,
        v2.VoteTypeId,
        v2.UserId,
        v2.CreationDate,
        rv.Level + 1
    from Votes v2
    inner join RecursiveVotes rv on v2.PostId = rv.PostId and v2.CreationDate > rv.CreationDate
    where v2.VoteTypeId in (2,3) and rv.Level < 3
), LatestUserReputation as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        rank() over (partition by u.Id order by u.LastAccessDate desc) as UserRank
    from Users u
), QuestionAnswerStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score as QuestionScore,
        p.ViewCount,
        p.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        row_number() over (partition by p.Id order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(a.Id) over (partition by p.Id) as TotalAnswers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
), CloseReasonCount as (
    select 
        ph.Comment as CloseReasonId,
        count(*) as CloseCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by ph.Comment
), UserBadgeRanks as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by b.UserId order by count(*) desc) as BadgeRank
    from Badges b
    group by b.UserId, b.Class
), CombinedUserData as (
    select 
        u.Id as UserId,
        u.DisplayName,
        coalesce(ub.Gold,0) as GoldBadges,
        coalesce(ub.Silver,0) as SilverBadges,
        coalesce(ub.Bronze,0) as BronzeBadges,
        u.Reputation,
        u.CreationDate,
        coalesce(qas.QuestionCount,0) as QuestionCount,
        coalesce(qas.AnswerCount,0) as AnswerCount,
        coalesce(avgQScore.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(avgAScore.AvgAnswerScore,0) as AvgAnswerScore
    from Users u
    left join (
        select UserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by UserId
    ) qas on qas.UserId = u.Id
    left join (
        select OwnerUserId as UserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) qas2 on qas2.UserId = u.Id
    left join (
        select OwnerUserId as UserId, avg(Score) as AvgQuestionScore
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) avgQScore on avgQScore.UserId = u.Id
    left join (
        select OwnerUserId as UserId, avg(Score) as AvgAnswerScore
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) avgAScore on avgAScore.UserId = u.Id
    left join (
        select 
            UserId,
            sum(case when Class = 1 then BadgeCount else 0 end) as Gold,
            sum(case when Class = 2 then BadgeCount else 0 end) as Silver,
            sum(case when Class = 3 then BadgeCount else 0 end) as Bronze
        from UserBadgeRanks
        group by UserId
    ) ub on ub.UserId = u.Id
)
select 
    cud.UserId,
    cud.DisplayName,
    cud.Reputation,
    cud.QuestionCount,
    cud.AnswerCount,
    cud.AvgQuestionScore,
    cud.AvgAnswerScore,
    cud.GoldBadges,
    cud.SilverBadges,
    cud.BronzeBadges,
    qas.QuestionId,
    qas.Title,
    qas.QuestionScore,
    qas.ViewCount,
    qas.TotalAnswers,
    qas.AnswerId,
    qas.AnswerScore,
    qas.AnswerRank,
    crc.CloseReasonId,
    crc.CloseCount,
    case when rv.Level is null then 'No recent votes' 
         else concat('Vote Type: ', rv.VoteTypeId, ', VoteId: ', rv.VoteId, ', Level: ', rv.Level) end as RecentVotesInfo,
    case 
        when cud.AvgAnswerScore > cud.AvgQuestionScore then 'Better answerer'
        when cud.AvgAnswerScore < cud.AvgQuestionScore then 'Better questioner'
        else 'Balanced' 
    end as UserPerformanceCategory,
    substring(coalesce(p.Body, '') from 1 for 100) || '...' as QuestionSnippet
from CombinedUserData cud
left join QuestionAnswerStats qas on qas.OwnerUserId = cud.UserId and qas.AnswerRank = 1
left join CloseReasonCount crc on crc.CloseReasonId = (
    select ph.Comment 
    from PostHistory ph 
    where ph.PostId = qas.QuestionId and ph.PostHistoryTypeId = 10 
    order by ph.CreationDate desc limit 1
)
left join RecursiveVotes rv on rv.PostId = qas.QuestionId
left join Posts p on p.Id = qas.QuestionId
where cud.Reputation > 1000
order by cud.Reputation desc, qas.QuestionScore desc
limit 100;