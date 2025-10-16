-- {"query": "426.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1381} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        r.Level + 1,
        r.Path || ' > ' || child.TagName
    from Tags child
    join RecursiveTagHierarchy r on child.Id = r.Id + 1
    where child.IsRequired = 1 and r.Level < 3
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScore,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc) as RecentRank
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
),
TopPostsWithComments as (
    select
        psr.Id as PostId,
        psr.PostTypeId,
        psr.OwnerUserId,
        psr.Score,
        psr.ViewCount,
        psr.CreationDate,
        psr.Title,
        psr.RankByScore,
        psr.RecentRank,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(c.MaxCommentScore, 0) as MaxCommentScore,
        coalesce(c.AvgCommentLength, 0) as AvgCommentLength
    from PostScoreRanks psr
    left join (
        select
            PostId,
            count(*) as CommentCount,
            max(Score) as MaxCommentScore,
            avg(length(Text)) as AvgCommentLength
        from Comments
        group by PostId
    ) c on c.PostId = psr.Id
    where psr.RankByScore <= 100
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCast,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as ReopenVotesCast
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBadges
),
DuplicatePostPairs as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        u1.DisplayName as OwnerUser,
        u2.DisplayName as RelatedOwnerUser,
        pl.CreationDate as LinkCreated,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u1 on u1.Id = p1.OwnerUserId
    left join Users u2 on u2.Id = p2.OwnerUserId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3 -- duplicates
),
FinalResult as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.AnswerCount,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.CloseVotesCast,
        u.ReopenVotesCast,
        p.PostId,
        p.Title as PostTitle,
        p.Score as PostScore,
        p.ViewCount,
        p.CommentCount,
        p.MaxCommentScore,
        p.AvgCommentLength,
        dt.PostId as DuplicatePostId,
        dt.RelatedPostId as DuplicateOfPostId,
        dt.PostTitle as DuplicatePostTitle,
        dt.RelatedPostTitle as OriginalPostTitle,
        dt.LinkCreated,
        dt.LinkTypeName,
        rh.Level as TagHierarchyLevel,
        rh.Path as TagPath
    from UserActivitySummary u
    left join TopPostsWithComments p on p.OwnerUserId = u.UserId and p.RankByScore <= 10
    left join DuplicatePostPairs dt on dt.PostId = p.PostId
    left join RecursiveTagHierarchy rh on rh.TagName = any(string_to_array(coalesce(p.Title, ''), ' '))
    where u.Reputation > 1000
    order by u.Reputation desc, p.Score desc nulls last
    limit 100
)
select * from FinalResult;