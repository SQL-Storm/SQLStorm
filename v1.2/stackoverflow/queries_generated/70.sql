-- {"query": "70.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1638} 
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
    join RecursiveTagHierarchy r on t2.Id = r.Id + 1
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
PostScoreStats as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.CreationDate as PostCreationDate,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
TopUserPosts as (
    select
        UserId,
        PostId,
        PostTypeId,
        PostScore,
        PostCreationDate,
        Title,
        Tags,
        ViewCount,
        AnswerCount,
        FavoriteCount,
        IsClosed,
        row_number() over (partition by UserId order by PostScore desc, PostCreationDate desc) as PostRank
    from UserActivityWindow
    where RecentPostRank <= 50
),
PostCommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as TotalCommentScore,
        max(c.Score) as MaxCommentScore,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        count(distinct pl.RelatedPostId) as RelatedPostsCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
        count(distinct ph.UserId) as UniqueClosers,
        string_agg(distinct crt.Name, ', ') as CloseReasonNames
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserVoteStats as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast,
        count(*) as TotalVotesCast
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.UserId
),
UserAggregated as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges,
        coalesce(pss.QuestionCount,0) as QuestionCount,
        coalesce(pss.AnswerCount,0) as AnswerCount,
        coalesce(pss.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(pss.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(uvs.UpVotesCast,0) as UpVotesCast,
        coalesce(uvs.DownVotesCast,0) as DownVotesCast,
        coalesce(uvs.FavoritesCast,0) as FavoritesCast
    from Users u
    left join UserBadgeCounts ubc on u.Id = ubc.UserId
    left join PostScoreStats pss on u.Id = pss.OwnerUserId
    left join UserVoteStats uvs on u.Id = uvs.UserId
    where u.Reputation > 500
)
select
    ua.Id as UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgQuestionScore,
    ua.AvgAnswerScore,
    ua.UpVotesCast,
    ua.DownVotesCast,
    ua.FavoritesCast,
    tup.PostId,
    tup.Title,
    tup.PostScore,
    tup.PostCreationDate,
    tup.Tags,
    tup.ViewCount,
    tup.AnswerCount as PostAnswerCount,
    tup.FavoriteCount,
    tup.IsClosed,
    pca.CommentCount,
    pca.TotalCommentScore,
    pca.MaxCommentScore,
    pca.Commenters,
    pld.DuplicateCount,
    pld.RelatedPostsCount,
    phcr.CloseEvents,
    phcr.UniqueClosers,
    phcr.CloseReasonNames,
    rh.Level as TagHierarchyLevel,
    rh.Path as TagHierarchyPath
from UserAggregated ua
left join TopUserPosts tup on ua.Id = tup.UserId and tup.PostRank = 1
left join PostCommentsAgg pca on tup.PostId = pca.PostId
left join PostLinkDuplicates pld on tup.PostId = pld.PostId
left join PostHistoryCloseReasons phcr on tup.PostId = phcr.PostId
left join RecursiveTagHierarchy rh on rh.TagName = any(string_to_array(coalesce(tup.Tags, ''), '><'))
where tup.PostId is not null
order by ua.Reputation desc, tup.PostScore desc
limit 100;