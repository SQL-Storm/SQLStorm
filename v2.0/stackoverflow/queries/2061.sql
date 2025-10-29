-- {"query": "2061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1436}
with RecursiveUserStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        coalesce(sum(vp.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vp.DownVotes),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > u.CreationDate
    left join (
        select 
            p.OwnerUserId,
            count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
            count(case when v.VoteTypeId = 3 then 1 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vp on vp.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
), BadgeAggregates as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as UniqueBadges
    from Badges b
    group by b.UserId
), TopPosts as (
    select 
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc NULLS LAST, p.ViewCount desc NULLS LAST) as rn
    from Posts p
    where p.PostTypeId in (1,2) and p.Score is not null
), PostLinkInfo as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.PostTypeId as PostTypeId,
        p2.PostTypeId as RelatedPostTypeId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
), TagExplode as (
    select 
        p.Id as PostId,
        trim(both '<>' from unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'))) as Tag
    from Posts p
    where p.Tags is not null and p.Tags <> ''
), QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
), UserCommentStats as (
    select 
        u.Id as UserId,
        count(c.Id) as TotalComments,
        count(distinct c.PostId) as DistinctPostsCommented,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Comments c on c.UserId = u.Id
    group by u.Id
), CloseReasonCounts as (
    select 
        pht.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(distinct pht.PostId) as PostsClosedCount
    from PostHistory pht
    join CloseReasonTypes crt on crt.Id = CAST(pht.Comment AS INTEGER)
    where pht.PostHistoryTypeId = 10
    group by pht.Comment, crt.Name, crt.Id
), RecursiveTagCounts as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        coalesce(pe.ParentCount, 0) as ParentTagCount
    from Tags t
    left join (
        select 
            p.Id,
            count(*) as ParentCount
        from PostLinks pl
        join Posts p on p.Id = pl.PostId
        where p.PostTypeId = 1
        group by p.Id
    ) pe on pe.Id = t.ExcerptPostId
)
select 
    rus.UserId,
    rus.DisplayName,
    rus.Reputation,
    rus.TotalPosts,
    rus.QuestionsCount,
    rus.AnswersCount,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.UniqueBadges,
    tp.PostId as TopPostId,
    tp.Title as TopPostTitle,
    tp.Score as TopPostScore,
    tp.ViewCount as TopPostViews,
    qa.TotalAnswers,
    qa.MaxAnswerScore,
    round(CAST(qa.AvgAnswerScore AS numeric),2) as AvgAnswerScore,
    ucs.TotalComments,
    ucs.DistinctPostsCommented,
    ucs.LastCommentDate,
    cr.CloseReasonName,
    cr.PostsClosedCount,
    rtc.TagName,
    rtc.Count as TagCount,
    rtc.ParentTagCount,
    concat('User location: ', coalesce(rus.Location,'Unknown'), '; Reputation Rank: ', rus.ReputationRank) as InfoSummary
from RecursiveUserStats rus
left join BadgeAggregates ba on ba.UserId = rus.UserId
left join TopPosts tp on tp.OwnerUserId = rus.UserId and tp.rn = 1
left join QuestionAnswerStats qa on qa.QuestionId = tp.PostId
left join UserCommentStats ucs on ucs.UserId = rus.UserId
left join (
    select cr.CloseReasonName, cr.PostsClosedCount
    from CloseReasonCounts cr
    order by cr.PostsClosedCount desc
    limit 1
) cr on true
left join RecursiveTagCounts rtc on rtc.TagName = (select Tag from TagExplode where PostId = tp.PostId limit 1)
where rus.TotalPosts > 50
order by rus.Reputation desc, rus.TotalPosts desc
limit 100;