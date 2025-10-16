-- {"query": "276.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1787} 
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
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(c.CommentCount, 0) as CommentCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScore
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserVoteSummary as (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.TotalBadges,
    pss.QuestionCount,
    pss.AnswerCount,
    pss.AvgQuestionScore,
    pss.AvgAnswerScore,
    pss.MaxQuestionScore,
    pss.MaxAnswerScore,
    coalesce(uvs.UpVotes,0) as TotalUpVotes,
    coalesce(uvs.DownVotes,0) as TotalDownVotes,
    coalesce(uvs.Favorites,0) as TotalFavorites,
    coalesce(uvs.CloseVotes,0) as TotalCloseVotes,
    ua.CumulativeQuestions,
    ua.CumulativeAnswers,
    dt.DuplicateCount,
    string_agg(distinct rth.Path, ' | ') as SampleTagPaths,
    tp.Title as TopQuestionTitle,
    tp.Score as TopQuestionScore,
    tp.CommentCount as TopQuestionComments,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateOfTitle
from Users u
left join UserBadgeCounts ubc on ubc.UserId = u.Id
left join PostScoreStats pss on pss.OwnerUserId = u.Id
left join UserActivityWindow ua on ua.UserId = u.Id and ua.RecentPostRank = 1
left join UserVoteSummary uvs on uvs.UserId = u.Id
left join (
    select OwnerUserId, count(*) as DuplicateCount
    from Posts p
    join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    group by OwnerUserId
) dt on dt.OwnerUserId = u.Id
left join RecursiveTagHierarchy rth on rth.Id in (
    select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')::int[])
    from Posts p where p.OwnerUserId = u.Id limit 1
)
left join (
    select p.OwnerUserId, p.Title, p.Score, c.CommentCount
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId = 1
    order by p.Score desc
    limit 1
) tp on tp.OwnerUserId = u.Id
left join (
    select pl.PostId, pl.RelatedPostId, p1.Title as PostTitle, p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
    limit 1
) dup on dup.PostId = (
    select p.Id from Posts p where p.OwnerUserId = u.Id order by p.CreationDate desc limit 1
)
where u.Reputation > 1000
group by
    u.Id, u.DisplayName, u.Reputation,
    ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ubc.TotalBadges,
    pss.QuestionCount, pss.AnswerCount, pss.AvgQuestionScore, pss.AvgAnswerScore, pss.MaxQuestionScore, pss.MaxAnswerScore,
    uvs.UpVotes, uvs.DownVotes, uvs.Favorites, uvs.CloseVotes,
    ua.CumulativeQuestions, ua.CumulativeAnswers,
    dt.DuplicateCount,
    tp.Title, tp.Score, tp.CommentCount,
    dup.PostTitle, dup.RelatedPostTitle
order by u.Reputation desc
limit 50;