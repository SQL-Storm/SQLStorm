-- {"query": "659.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1406} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        array[t.TagName] as TagPath
    from Tags t
    where t.IsModeratorOnly = 0
    union all
    select 
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.TagPath || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and not t.TagName = any(r.TagPath)
    where t.IsModeratorOnly = 0 and r.Level < 2
),
UserBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    where u.Reputation > 1000
),
PostAnswerStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate as QuestionCreation,
        count(a.Id) as TotalAnswers,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        (select count(*) from Comments c where c.PostId = p.Id) as QuestionCommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotesOnQuestion,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotesOnQuestion
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate
),
TopQuestionsWithUserInfo as (
    select 
        pas.QuestionId,
        pas.Title,
        pas.TotalAnswers,
        pas.PositiveAnswers,
        pas.MaxAnswerScore,
        pas.MinAnswerScore,
        pas.AvgAnswerScore,
        pas.QuestionCommentCount,
        pas.UpVotesOnQuestion,
        pas.DownVotesOnQuestion,
        urs.DisplayName as QuestionOwnerName,
        urs.Reputation as QuestionOwnerReputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        urs.Location,
        urs.RepRank,
        row_number() over (partition by urs.Location order by pas.UpVotesOnQuestion desc, pas.TotalAnswers desc) as LocationRank
    from PostAnswerStats pas
    left join UserReputationStats urs on urs.Id = pas.OwnerUserId
    where pas.TotalAnswers > 5
)
select 
    tqwu.QuestionId,
    tqwu.Title,
    tqwu.TotalAnswers,
    tqwu.PositiveAnswers,
    tqwu.MaxAnswerScore,
    tqwu.MinAnswerScore,
    round(tqwu.AvgAnswerScore,2) as AvgAnswerScore,
    tqwu.QuestionCommentCount,
    tqwu.UpVotesOnQuestion,
    tqwu.DownVotesOnQuestion,
    coalesce(tqwu.QuestionOwnerName, 'Unknown') as QuestionOwnerName,
    tqwu.QuestionOwnerReputation,
    tqwu.GoldBadges,
    tqwu.SilverBadges,
    tqwu.BronzeBadges,
    coalesce(tqwu.Location, 'Unknown') as Location,
    tqwu.RepRank,
    tqwu.LocationRank,
    string_agg(distinct rth.TagName, ', ') as RelatedTags,
    case 
        when tqwu.UpVotesOnQuestion > 100 then 'Hot'
        when tqwu.UpVotesOnQuestion between 50 and 100 then 'Warm'
        else 'Cold'
    end as PopularityCategory
from TopQuestionsWithUserInfo tqwu
left join Posts p on p.Id = tqwu.QuestionId
left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(p.Tags, '')) > 0
where tqwu.LocationRank <= 3
group by 
    tqwu.QuestionId,
    tqwu.Title,
    tqwu.TotalAnswers,
    tqwu.PositiveAnswers,
    tqwu.MaxAnswerScore,
    tqwu.MinAnswerScore,
    tqwu.AvgAnswerScore,
    tqwu.QuestionCommentCount,
    tqwu.UpVotesOnQuestion,
    tqwu.DownVotesOnQuestion,
    tqwu.QuestionOwnerName,
    tqwu.QuestionOwnerReputation,
    tqwu.GoldBadges,
    tqwu.SilverBadges,
    tqwu.BronzeBadges,
    tqwu.Location,
    tqwu.RepRank,
    tqwu.LocationRank
union
select 
    p.Id as QuestionId,
    p.Title,
    0 as TotalAnswers,
    0 as PositiveAnswers,
    null as MaxAnswerScore,
    null as MinAnswerScore,
    null as AvgAnswerScore,
    0 as QuestionCommentCount,
    0 as UpVotesOnQuestion,
    0 as DownVotesOnQuestion,
    'Community' as QuestionOwnerName,
    0 as QuestionOwnerReputation,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    'N/A' as Location,
    null as RepRank,
    null as LocationRank,
    '' as RelatedTags,
    'Cold' as PopularityCategory
from Posts p
where p.PostTypeId = 1 and p.OwnerUserId is null
order by PopularityCategory desc, TotalAnswers desc, UpVotesOnQuestion desc
limit 100;