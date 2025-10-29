-- {"query": "2207.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1562} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersPosted,
        coalesce(sum(vtUp.CountUpVotes),0) as TotalUpVotesReceived,
        coalesce(sum(vtDown.CountDownVotes),0) as TotalDownVotesReceived,
        row_number() over (partition by u.Location order by u.Reputation desc) as RankInLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts p2 on p2.OwnerUserId = u.Id and p2.PostTypeId = 2
    left join (
        select p.OwnerUserId, count(*) as CountUpVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        join Posts p on p.Id = v.PostId
        where vt.Name = 'UpMod'
        group by p.OwnerUserId
    ) vtUp on vtUp.OwnerUserId = u.Id
    left join (
        select p.OwnerUserId, count(*) as CountDownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        join Posts p on p.Id = v.PostId
        where vt.Name = 'DownMod'
        group by p.OwnerUserId
    ) vtDown on vtDown.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeAwarded
    from Badges b
    group by b.UserId
),
TopUsers as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.TotalUpVotesReceived,
        ua.TotalDownVotesReceived,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.LastBadgeAwarded
    from RecursiveUserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
    where ua.RankInLocation <= 10
),
PostWithStats as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        count(distinct c.Id) as CommentCount,
        max(ph.CreationDate) as LastEditDate,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6,7,8,9,14)
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.AcceptedAnswerId
),
TopTags as (
    select
        tg.Id,
        tg.TagName,
        tg.Count,
        coalesce(pws.QuestionCount, 0) as PopularQuestions,
        coalesce(pws.AverageScore, 0) as AvgQuestionScore
    from Tags tg
    left join (
        select
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as TagName,
            count(*) filter (where p.PostTypeId = 1) as QuestionCount,
            avg(p.Score) filter (where p.PostTypeId = 1) as AverageScore
        from Posts p
        where p.Tags is not null
        group by TagName
    ) pws on pws.TagName = tg.TagName
    where tg.Count > 1000
    order by tg.Count desc
    limit 20
)
select
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.Location,
    tu.QuestionsPosted,
    tu.AnswersPosted,
    tu.TotalUpVotesReceived,
    tu.TotalDownVotesReceived,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.LastBadgeAwarded,
    pt.Id as PostId,
    pt.Title,
    pt.Score,
    pt.ViewCount,
    pt.CommentCount,
    pt.HasAcceptedAnswer,
    tg.TagName,
    tg.Count as TagGlobalCount,
    tg.PopularQuestions,
    tg.AvgQuestionScore,
    dense_rank() over (partition by pt.OwnerUserId order by pt.Score desc) as PostRankByScore,
    dense_rank() over (partition by tg.TagName order by pt.Score desc nulls last) as PostRankInTag,
    coalesce(
        (select count(*) from Votes v 
         join VoteTypes vt on v.VoteTypeId = vt.Id and vt.Name = 'Favorite' 
         where v.PostId = pt.Id), 0
    ) as FavoriteCount
from TopUsers tu
left join PostWithStats pt on pt.OwnerUserId = tu.UserId and pt.PostTypeId = 1 and pt.Score > 10
left join TopTags tg on tg.TagName = any(string_to_array(substring(pt.Tags, 2, length(pt.Tags) - 2), '><'))
where pt.CreationDate > tu.CreationDate + interval '30 days' -- posts at least 30 days after user creation
union
select
    -1 as UserId,
    'Community' as DisplayName,
    0 as Reputation,
    null as Location,
    0 as QuestionsPosted,
    0 as AnswersPosted,
    0 as TotalUpVotesReceived,
    0 as TotalDownVotesReceived,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    null as LastBadgeAwarded,
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    0 as HasAcceptedAnswer,
    tg.TagName,
    tg.Count as TagGlobalCount,
    tg.PopularQuestions,
    tg.AvgQuestionScore,
    null as PostRankByScore,
    null as PostRankInTag,
    0 as FavoriteCount
from Posts p
left join TopTags tg on tg.TagName = any(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
where p.OwnerUserId = -1 and p.PostTypeId = 1 and p.Score > 50
order by Reputation desc nulls last, Score desc nulls last, FavoriteCount desc nulls last
limit 100;