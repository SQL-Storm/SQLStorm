-- {"query": "2792.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1406} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Ancestors
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1 as Level,
        r.Ancestors || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Ancestors)
    where t.IsModeratorOnly = 0
), QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        u.DisplayName as OwnerName,
        p.CreationDate,
        p.Score as QuestionScore,
        coalesce(p.ViewCount, 0) as ViewCount,
        p.AnswerCount,
        coalesce(a.AnswerCount, 0) as ActualAnswerCount,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
        p.Tags
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select
            ParentId,
            count(*) as AnswerCount,
            max(Score) as MaxAnswerScore,
            avg(Score) as AvgAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = p.Id
    where p.PostTypeId = 1
), PostVotesAgg as (
    select
        p.Id as PostId,
        p.PostTypeId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBountyGiven
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId
), LatestPostHistories as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.UserDisplayName,
        ph.CreationDate,
        ph.Comment
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11,12,13,19,20)
    order by ph.PostId, ph.CreationDate desc
), TopUsersByReputation as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RankByReputation
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(b.Id) > 0
    order by u.Reputation desc
    limit 100
)
select 
    q.QuestionId,
    q.Title,
    coalesce(q.OwnerName, 'Unknown') as OwnerName,
    q.CreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.ActualAnswerCount,
    round(q.MaxAnswerScore::numeric,2) as MaxAnswerScore,
    round(q.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    v.UpVotes,
    v.DownVotes,
    v.Favorites,
    v.TotalBountyGiven,
    lh.PostHistoryTypeId as LatestClosureOrProtection,
    lh.Comment as ClosureReasonOrComment,
    array_to_string(array_agg(distinct rt.TagName), ', ') as RequiredTagsInHierarchy,
    u.DisplayName as TopUserDisplayName,
    u.Reputation as TopUserReputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    dense_rank() over (partition by q.OwnerName order by q.QuestionScore desc) as QuestionScoreRankWithinOwner,
    case 
        when q.ViewCount > 10000 then 'High Views'
        when q.ViewCount between 1000 and 10000 then 'Medium Views'
        else 'Low Views'
    end as ViewCategory,
    case 
        when q.AvgAnswerScore is null then 'No Answers'
        when q.AvgAnswerScore > 5 then 'Highly Rated Answers'
        when q.AvgAnswerScore between 1 and 5 then 'Moderate Answers'
        else 'Low Rated Answers'
    end as AnswerQualityCategory,
    length(q.Title) as TitleLength,
    strpos(lower(q.Title), 'sql') > 0 as TitleContainsSQL,
    coalesce((select count(*) from Comments c where c.PostId = q.QuestionId and c.Score > 0),0) as PositiveCommentsCount,
    coalesce((select count(*) from Comments c where c.PostId = q.QuestionId and c.Score < 0),0) as NegativeCommentsCount
from QuestionAnswerStats q
left join PostVotesAgg v on v.PostId = q.QuestionId
left join LatestPostHistories lh on lh.PostId = q.QuestionId
left join RecursiveTagHierarchy rt on rt.TagName = any(string_to_array(regexp_replace(q.Tags, '[<>]', ',', 'g'), ','))
left join TopUsersByReputation u on u.DisplayName = q.OwnerName
where q.QuestionScore > 500
and (lh.PostHistoryTypeId is null or lh.PostHistoryTypeId in (10,11))
group by q.QuestionId, q.Title, q.OwnerName, q.CreationDate, q.QuestionScore, q.ViewCount, q.AnswerCount, q.ActualAnswerCount, q.MaxAnswerScore, q.AvgAnswerScore, v.UpVotes, v.DownVotes, v.Favorites, v.TotalBountyGiven, lh.PostHistoryTypeId, lh.Comment, u.DisplayName, u.Reputation, u.GoldBadges, u.SilverBadges, u.BronzeBadges
order by q.QuestionScore desc, q.ViewCount desc
limit 50;