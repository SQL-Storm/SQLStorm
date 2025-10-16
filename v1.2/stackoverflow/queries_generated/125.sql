-- {"query": "125.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1750} 
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
PostScoreStats as (
    select
        p.OwnerUserId,
        count(*) as TotalPosts,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount
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
        row_number() over (partition by u.Id order by ph.CreationDate desc) as RecentEditRank,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate as EditDate,
        ph.Comment as EditComment
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
),
TopPostsWithComments as (
    select
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
DuplicateQuestions as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate as LinkDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserPostActivity as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as Questions,
        count(*) filter (where p.PostTypeId = 2) as Answers,
        count(*) filter (where p.PostTypeId not in (1,2)) as OtherPosts,
        max(p.CreationDate) as LastPostDate
    from Posts p
    group by p.OwnerUserId
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TotalBadges,
        coalesce(upa.Questions,0) as Questions,
        coalesce(upa.Answers,0) as Answers,
        coalesce(upa.OtherPosts,0) as OtherPosts,
        upa.LastPostDate
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join UserPostActivity upa on upa.OwnerUserId = u.Id
)
select
    ubs.UserId,
    ubs.DisplayName,
    ubs.ReputationRank,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalBadges,
    ubs.Questions,
    ubs.Answers,
    ubs.OtherPosts,
    ubs.LastPostDate,
    coalesce(pss.TotalPosts,0) as TotalPosts,
    coalesce(pss.AvgScore,0) as AvgPostScore,
    coalesce(pss.MaxScore,0) as MaxPostScore,
    coalesce(pss.MinScore,0) as MinPostScore,
    array_agg(distinct rth.Path order by rth.Level) filter (where rth.Path is not null) as TagPaths,
    (select count(*) from DuplicateQuestions dq where dq.PostId in (
        select p.Id from Posts p where p.OwnerUserId = ubs.UserId and p.PostTypeId = 1
    )) as DuplicateQuestionsCount,
    (select count(*) from Votes v where v.UserId = ubs.UserId and v.VoteTypeId = 2) as TotalUpVotesCast,
    (select count(*) from Votes v where v.UserId = ubs.UserId and v.VoteTypeId = 3) as TotalDownVotesCast,
    (select count(*) from Comments c where c.UserId = ubs.UserId) as TotalCommentsMade,
    (select max(ph.CreationDate) from PostHistory ph where ph.UserId = ubs.UserId) as LastEditDate
from UserBadgeSummary ubs
left join UserReputationRank urr on urr.Id = ubs.UserId
left join PostScoreStats pss on pss.OwnerUserId = ubs.UserId
left join RecursiveTagHierarchy rth on rth.TagName = any(
    select unnest(string_to_array(coalesce(p.Tags,''), '><'))
    from Posts p where p.OwnerUserId = ubs.UserId limit 1
)
where ubs.TotalBadges > 0 and ubs.Questions > 5
group by
    ubs.UserId,
    ubs.DisplayName,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalBadges,
    ubs.Questions,
    ubs.Answers,
    ubs.OtherPosts,
    ubs.LastPostDate,
    pss.TotalPosts,
    pss.AvgScore,
    pss.MaxScore,
    pss.MinScore,
    urr.ReputationRank
order by ubs.TotalBadges desc, ubs.Questions desc, ubs.Answers desc
limit 50;