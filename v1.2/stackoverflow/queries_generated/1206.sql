-- {"query": "1206.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1278} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(pans.AnswerCount, 0) as TotalAnswers,
        coalesce(pq.FavSum, 0) as TotalFavorites,
        dense_rank() over (order by t.Count desc) as RankByCount
    from Tags t
    left join (
        select pt.Id, count(pa.Id) as AnswerCount
        from Posts pt
        left join Posts pa on pa.ParentId = pt.Id and pa.PostTypeId = 2 -- Answers
        where pt.PostTypeId = 1 -- Questions
        group by pt.Id
    ) pans on pans.Id = t.ExcerptPostId
    left join (
        select ParentId, sum(FavoriteCount) as FavSum
        from Posts
        where PostTypeId = 1
        group by ParentId
    ) pq on pq.ParentId = t.WikiPostId
    where t.TagName is not null
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by max(b.Date) desc nulls last) as BadgeRecencyRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivitySummary as (
    select 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        case 
            when p.AcceptedAnswerId is not null then 1 
            else 0 
        end as IsAcceptedQuestion,
        lead(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostAfter,
        rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank,
        nvl(
            (select avg(v2.Score) from Posts v2 where v2.OwnerUserId = p.OwnerUserId and v2.PostTypeId = p.PostTypeId), 
            0) as AvgUserPostScore,
        nvl(
            (select count(*) from Comments c2 where c2.PostId = p.Id and c2.UserId <> p.OwnerUserId), 
            0) as CommentsByOthers
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
CommentsThematic as (
    select
        c.PostId,
        count(*) as TotalComments,
        sum(case when lower(c.Text) ~ 'bug|error|fail|issue' then 1 else 0 end) as CriticalComments,
        sum(case when length(c.Text) > 300 then 1 else 0 end) as LongComments,
        min(c.CreationDate) as FirstCommentDate,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
PostHistoryCloseStats as (
    select
        p.Id,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 10) as TimesClosed,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 11) as TimesReopened,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id
)
select 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerName,
    p.IsAcceptedQuestion,
    p.NextPostAfter,
    p.ScoreRank,
    p.AvgUserPostScore,
    p.CommentsByOthers,
    ct.TotalComments,
    ct.CriticalComments,
    ct.LongComments,
    ct.FirstCommentDate,
    ct.LastCommentDate,
    phc.TimesClosed,
    phc.TimesReopened,
    phc.LastCloseDate,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    case 
        when ub.GoldBadges > 10 then 'Elite User'
        when ub.SilverBadges > 20 then 'Advanced User'
        when ub.BronzeBadges > 50 then 'Active User'
        else 'Standard User'
    end as UserStatus,
    rc.TagName,
    rc.Count as TagCount,
    rc.TotalAnswers,
    rc.TotalFavorites,
    rc.RankByCount,
    concat(
        coalesce(u.Location, 'Unknown'),
        ' | ', substring(coalesce(u.AboutMe, 'No Info'), 1, 50),
        ' | Rep: ', u.Reputation::text) as UserSummary
from PostActivitySummary p
left join CommentsThematic ct on ct.PostId = p.Id
left join PostHistoryCloseStats phc on phc.Id = p.Id
left join Users u on u.DisplayName = p.OwnerName
left join UserBadgeCounts ub on ub.UserId = u.Id
left join LATERAL (
    select t.TagName, t.Count, t.TotalAnswers, t.TotalFavorites, t.RankByCount
    from RecursiveTagCounts t
    where	p.Tags ilike concat('%<', t.TagName, '>%') -- assuming Tags is XML-like: <tag1><tag2>
    order by t.Count desc nulls last
    limit 1
) rc on true
where p.Score > 10
and (p.Tags is not null and length(p.Tags) > 2)
order by p.ScoreRank
limit 100;