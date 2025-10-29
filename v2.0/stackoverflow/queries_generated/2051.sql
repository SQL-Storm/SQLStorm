-- {"query": "2051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1556} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.ExcerptPostId = r.Id
    where t.Id <> all(r.Path)
), UserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId = 8 -- BountyStart
    group by u.Id, u.DisplayName, u.Reputation
), PostsWithDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        pa.Score as AcceptedAnswerScore,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select coalesce(sum(vp.Score),0) from Votes vp where vp.PostId = p.Id and vp.VoteTypeId = 2) as UpVotesForPost,
        (select coalesce(sum(vd.Score),0) from Votes vd where vd.PostId = p.Id and vd.VoteTypeId = 3) as DownVotesForPost,
        case 
            when p.ClosedDate is null then false 
            else true 
        end as IsClosed
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    left join Posts pa on pa.Id = p.AcceptedAnswerId
), UserRankedPosts as (
    select
        pwd.*,
        us.ReputationRank,
        rank() over (partition by pwd.OwnerUserId order by pwd.Score desc, pwd.ViewCount desc) as PostRankPerUser,
        dense_rank() over (order by pwd.Score desc nulls last) as GlobalPostScoreRank
    from PostsWithDetails pwd
    join UserStats us on us.UserId = pwd.OwnerUserId
), CloseReasonCounts as (
    select
        cht.Name as CloseReasonName,
        count(distinct ph.PostId) as ClosedPostCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    join CloseReasonTypes cht on cht.Id::varchar = ph.Comment -- stored as string, so cast accordingly
    group by cht.Name
), PostLinksWithType as (
    select
        pl.Id,
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts p1 on p1.Id = pl.PostId
    left join Posts p2 on p2.Id = pl.RelatedPostId
), QuestionsWithDuplicateAnswers as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        count(distinct a.Id) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        sum(case when a.Score >= 5 then 1 else 0 end) as HighScoreAnswerCount,
        max(a.Score) as MaxAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join PostLinks pl on pl.PostId = q.Id and pl.RelatedPostId = a.Id and pl.LinkTypeId = 3
    where q.PostTypeId = 1
    group by q.Id, q.Title
)
select
    urp.Id as PostId,
    urp.PostTypeName,
    urp.Title,
    urp.OwnerUserId,
    urp.OwnerDisplayName,
    urp.Score,
    urp.ViewCount,
    urp.CommentCount,
    urp.IsClosed,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TotalBountyGiven,
    crc.CloseReasonName,
    crc.ClosedPostCount,
    coalesce(plwt.LinkTypeName, 'No Link') as PostLinkType,
    plwt.RelatedPostTitle,
    qda.DuplicateCount,
    qda.HighScoreAnswerCount,
    qda.MaxAnswerScore,
    string_agg(distinct rth.TagName, ', ') as RecursiveTags
from UserRankedPosts urp
join UserStats us on us.UserId = urp.OwnerUserId
left join CloseReasonCounts crc on crc.CloseReasonName = (
    select cht.Name
    from PostHistory ph2
    join PostHistoryTypes pht2 on pht2.Id = ph2.PostHistoryTypeId and pht2.Name = 'Post Closed'
    join CloseReasonTypes cht on cht.Id::varchar = ph2.Comment
    where ph2.PostId = urp.Id
    order by ph2.CreationDate desc
    limit 1
)
left join PostLinksWithType plwt on plwt.PostId = urp.Id
left join QuestionsWithDuplicateAnswers qda on qda.QuestionId = urp.Id and urp.PostTypeId = 1
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(
    substring(coalesce(urp.Tags, ''), 2, length(coalesce(urp.Tags, '')) - 2),
    '><'
))
where urp.ReputationRank <= 100
and (urp.PostRankPerUser = 1 or urp.GlobalPostScoreRank <= 500)
group by 
    urp.Id,
    urp.PostTypeName,
    urp.Title,
    urp.OwnerUserId,
    urp.OwnerDisplayName,
    urp.Score,
    urp.ViewCount,
    urp.CommentCount,
    urp.IsClosed,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TotalBountyGiven,
    crc.CloseReasonName,
    crc.ClosedPostCount,
    plwt.LinkTypeName,
    plwt.RelatedPostTitle,
    qda.DuplicateCount,
    qda.HighScoreAnswerCount,
    qda.MaxAnswerScore
order by urp.Score desc nulls last, urp.ViewCount desc nulls last
limit 100;