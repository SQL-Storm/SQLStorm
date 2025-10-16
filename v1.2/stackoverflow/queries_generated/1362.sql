-- {"query": "1362.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1174} 
with TagStats as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
), TagAvgScores as (
    select
        ts.TagName,
        count(*) as QuestionCount,
        avg(p.Score) as AvgQuestionScore,
        max(p.Score) as MaxQuestionScore
    from TagStats ts
    join Posts p on p.Id = ts.PostId
    group by ts.TagName
), UserBadgesRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date) as BadgeRank
    from Badges b
), UserReputRank as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as RepRank
    from Users u
)
select
    u.DisplayName,
    COALESCE(u.Reputation,0) as Reputation,
    u.RepRank,
    coalesce(bc.GoldBadges,0) as GoldBadges,
    coalesce(bc.SilverBadges,0) as SilverBadges,
    coalesce(bc.BronzeBadges,0) as BronzeBadges,
    ts.TagName,
    ts.QuestionCount,
    ts.AvgQuestionScore,
    ts.MaxQuestionScore,
    case 
      when p.AcceptedAnswerId is not null then 'Accepted'
      when p.Score > 10 then 'HighlyScored'
      else 'Normal'
    end as QuestionStatus,
    coalesce(v.UpVotes,0) as UpVotesCount,
    coalesce(v.DownVotes,0) as DownVotesCount,
    (coalesce(v.UpVotes,0) * 1.0 / nullif( coalesce(v.DownVotes,0) + 1, 0 )) as UpDownRatio,
    c.LastComment,
    c.LastCommentDate
from UserReputRank u
left join (
    select 
        b.UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
) bc on bc.UserId = u.UserId
left join (
    select p.OwnerUserId, ts2.TagName, ts2.QuestionCount, ts2.AvgQuestionScore, ts2.MaxQuestionScore
    from TagAvgScores ts2
    join (
        select distinct p2.Id, p2.OwnerUserId from Posts p2 where p2.PostTypeId = 1
    ) p on ts2.TagName = any(string_to_array(substring(p.Id in (select PostId)::text from posts, 2, length((select Tags from posts where Id = p.Id)) - 2), '><'))
    where p.OwnerUserId is not null
) ts on ts.OwnerUserId = u.UserId
left join Posts p on p.OwnerUserId = u.UserId and p.PostTypeId = 1 and p.Score = (
    select max(p2.Score)
    from Posts p2
    where p2.OwnerUserId = u.UserId and p2.PostTypeId = 1
)
left join (
    select
        PostId,
        max(CreationDate) as LastCommentDate,
        substring(max(USERAGG || '::: ' || Text) from '#:', '#') as LastComment -- avoid environment interaction, simplified
    from (
        select c.PostId, c.CreationDate, 
               row_number() over (partition by c.PostId order by c.CreationDate desc) as rn, c.UserDisplayName || '::: ' || c.Text as USERAGG
        from Comments c
    ) c where rn = 1
    group by PostId
) c on c.PostId = p.Id
left join (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
) v on v.PostId = p.Id
where u.RepRank <= 100
union
select
    u.DisplayName,
    0 as Reputation,
    null as RepRank,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    null as TagName,
    0 as QuestionCount,
    null as AvgQuestionScore,
    null as MaxQuestionScore,
    'NoQuestions' as QuestionStatus,
    0 as UpVotesCount,
    0 as DownVotesCount,
    0 as UpDownRatio,
    null as LastComment,
    null as LastCommentDate
from Users u
where not exists (select 1 from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1)
order by Reputation desc nulls last, GoldBadges desc, SilverBadges desc, BronzeBadges desc
limit 250;