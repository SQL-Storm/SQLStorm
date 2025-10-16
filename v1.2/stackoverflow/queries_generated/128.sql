-- {"query": "128.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1560} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate) as CreationRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopPostsWithComments as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        coalesce(ub.TotalBadges, 0) as TotalBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as PostsClosed,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as PostsReopened
    from Users u
    left join Badges ub on ub.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBadges
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
ComplexPostAnalysis as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        case
            when p.AcceptedAnswerId is not null then 1
            else 0
        end as HasAcceptedAnswer,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select max(ph.CreationDate) from PostHistory ph where ph.PostId = p.Id) as LastEditDate,
        case
            when p.ClosedDate is not null then 'Closed'
            else 'Open'
        end as PostStatus,
        coalesce(p.Tags, '') like '%<sql>%' as HasSQLTag,
        length(p.Body) - length(replace(p.Body, '<code>', '')) as CodeSnippetCount
    from Posts p
    where p.PostTypeId = 1
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalBadges,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.PostsClosed,
    ua.PostsReopened,
    cpa.Id as QuestionId,
    cpa.Title as QuestionTitle,
    cpa.Score as QuestionScore,
    cpa.ViewCount as QuestionViews,
    cpa.HasAcceptedAnswer,
    cpa.UpVotes,
    cpa.DownVotes,
    cpa.CommentCount as QuestionCommentCount,
    cpa.LastEditDate,
    cpa.PostStatus,
    cpa.HasSQLTag,
    cpa.CodeSnippetCount,
    dt.Path as TagHierarchyPath,
    dt.Level as TagHierarchyLevel,
    dpl.RelatedPostId as DuplicateOfPostId,
    dpl.RelatedPostTitle as DuplicateOfPostTitle,
    dpl.CreationDate as DuplicateLinkDate,
    ts.CommentCount as TotalCommentsOnQuestion,
    ts.LastCommentDate,
    ts.Commenters
from UserActivitySummary ua
left join ComplexPostAnalysis cpa on cpa.OwnerUserId = ua.UserId
left join RecursiveTagHierarchy dt on dt.TagName = any(string_to_array(coalesce(cpa.Tags, ''), '><'))
left join DuplicateLinks dpl on dpl.PostId = cpa.Id
left join TopPostsWithComments ts on ts.PostId = cpa.Id
where ua.Reputation > 1000
  and (cpa.Score > 10 or cpa.ViewCount > 1000)
  and (dt.Level is null or dt.Level <= 2)
order by ua.Reputation desc, cpa.Score desc, cpa.ViewCount desc
limit 100;