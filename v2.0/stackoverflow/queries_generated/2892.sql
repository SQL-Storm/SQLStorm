-- {"query": "2892.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1568} 
with recursive UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        row_number() over (order by count(b.Id) desc nulls last) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
), RecursivePostTree as (
    select 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.OwnerUserId, 
        1 as Depth
    from Posts p
    where p.ParentId is null and p.PostTypeId = 1
    
    union all
    
    select 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.OwnerUserId,
        rpt.Depth + 1 
    from Posts p
    join RecursivePostTree rpt on p.ParentId = rpt.Id
    where p.PostTypeId = 2
), LatestPostHistoryPerPost as (
    select distinct on (ph.PostId) 
        ph.PostId, ph.Id as HistoryId, ph.PostHistoryTypeId, ph.CreationDate as HistoryDate,
        ph.UserId, ph.UserDisplayName, ph.Comment
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc, ph.Id desc
), PostVotesSummary as (
    select
        p.Id as PostId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as FavoriteVotes,
        sum(case when v.BountyAmount is not null then v.BountyAmount else 0 end) as TotalBounty
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id
), PostsWithLinkInfo as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        pls.DirectLinkCount,
        pls.DuplicateLinkCount
    from Posts p
    left join (
        select 
            pl.PostId,
            count(case when pl.LinkTypeId = 1 then 1 end) as DirectLinkCount,
            count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateLinkCount
        from PostLinks pl
        group by pl.PostId
    ) pls on pls.PostId = p.Id
), UserActivityRank as (
    select
        u.Id as UserId,
        count(distinct p.Id) over (partition by u.Id) as TotalPosts,
        count(distinct c.Id) over (partition by u.Id) as TotalComments,
        row_number() over (order by count(distinct p.Id) desc, count(distinct c.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
), QuestionsWithAnswersAndComments as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionCreated,
        count(distinct a.Id) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(coalesce(avote.UpVoteCount,0)) as AnswerUpVotes,
        sum(coalesce(avote.DownVoteCount,0)) as AnswerDownVotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Comments c on c.PostId = q.Id
    left join (
        select 
            v.PostId,
            count(case when v.VoteTypeId = 2 then 1 end) as UpVoteCount,
            count(case when v.VoteTypeId = 3 then 1 end) as DownVoteCount
        from Votes v
        group by v.PostId
    ) avote on avote.PostId = a.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.OwnerUserId, q.CreationDate
), TopTagsCTE as (
    select
        tag.TagName,
        tag.Count,
        row_number() over (order by tag.Count desc) as TagRank,
        (
            select count(1) from Posts p2 
            where p2.PostTypeId = 1 
              and p2.Tags is not null 
              and ('<'+tag.TagName+'>' = any(string_to_array(p2.Tags, '><'))) 
        ) as QuestionCount
    from Tags tag
), DuplicateQuestionLinks as (
    select 
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
)
select 
    ubc.UserId,
    ubc.DisplayName, 
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    uar.TotalPosts,
    uar.TotalComments,
    qac.QuestionId,
    qac.Title as QuestionTitle,
    qac.AnswerCount,
    qac.CommentCount,
    qac.AnswerUpVotes,
    qac.AnswerDownVotes,
    pts.TagName as TopTag,
    pts.QuestionCount as QuestionsWithTag,
    dql.DuplicateQuestionId,
    dql.OriginalQuestionId,
    dql.DuplicateTitle,
    dql.OriginalTitle,
    phl.HistoryDate as LastPostHistoryDate,
    phl.PostHistoryTypeId,
    phl.Comment as LastPostHistoryComment,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.FavoriteVotes,
    pvs.TotalBounty
from UserBadgeCounts ubc
left join UserActivityRank uar on uar.UserId = ubc.UserId
left join QuestionsWithAnswersAndComments qac on qac.QuestionOwner = ubc.UserId
left join TopTagsCTE pts on pts.TagRank = 1
left join DuplicateQuestionLinks dql on dql.DuplicateQuestionId = qac.QuestionId
left join LatestPostHistoryPerPost phl on phl.PostId = qac.QuestionId
left join PostVotesSummary pvs on pvs.PostId = qac.QuestionId
where ubc.BadgeRank <= 100
  and (qac.AnswerCount > 2 or qac.CommentCount > 5)
  and (phl.PostHistoryTypeId is null or phl.PostHistoryTypeId not in (10, 12))
order by ubc.BadgeRank, qac.QuestionCreated desc
limit 100;