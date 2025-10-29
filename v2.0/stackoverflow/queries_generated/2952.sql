-- {"query": "2952.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1856} 
with RecursiveTagHierarchy as (
    select 
        t.Id, 
        t.TagName, 
        t.Count,
        t.WikiPostId,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.WikiPostId,
        r.Level + 1
    from Tags t2
    join PostLinks pl on pl.PostId = t2.WikiPostId
    join RecursiveTagHierarchy r on r.Id = pl.RelatedPostId
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and r.Level < 3
),
RankedPosts as (
    select 
        p.Id, 
        p.PostTypeId, 
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        p.Score, 
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserPostRank,
        dense_rank() over (order by p.Score desc) as ScoreRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
),
PostScoresWithVotes as (
    select 
        p.Id as PostId,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotes,
        count(distinct v.UserId) as DistinctVoters
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
UserBadgeSummaries as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as UniqueBadges,
        max(b.Date) as LastBadgeAwarded
    from Badges b
    group by b.UserId
),
QuestionsWithDuplicateLinks as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        count(distinct pl.RelatedPostId) as DuplicateCount,
        max(ph.CreationDate) as LastClosedDate,
        -- correlated subquery to find duplicate original titles
        (select ph2.Text 
         from PostHistory ph2 
         where ph2.PostId = pl.RelatedPostId and ph2.PostHistoryTypeId = 1
         order by ph2.CreationDate asc limit 1) as DuplicateOriginalTitle
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        extract(epoch from u.LastAccessDate - u.CreationDate)/86400.0 as DaysActive,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        max(p.CreationDate) over (partition by u.Id) as LastPostDate,
        sum(v.UpVotes) as TotalUpVotes,
        sum(v.DownVotes) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, 
               sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
               sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.LastAccessDate, u.CreationDate
),
PostsWithComplexTags as (
    select 
        p.Id,
        p.Tags,
        string_agg(distinct rth.TagName, ', ') as RelatedTags,
        length(coalesce(p.Tags, '')) as TagsLength,
        p.Score,
        p.ViewCount,
        case 
            when p.Tags is null then 0
            when p.Tags like '%<sql>%'
                and p.Tags like '%<json>%'
                then 1 else 0 end as TagsContainingSqlAndJson,
        p.FavoriteCount
    from Posts p
    left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(p.Tags, '')) > 0
    where p.PostTypeId = 1
    group by p.Id, p.Tags, p.Score, p.ViewCount, p.FavoriteCount
),
CombinedSet as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.AnswerCount > 0
    union
    select 
        p2.Id,
        null as Title,
        p2.CreationDate,
        p2.OwnerUserId,
        p2.Score,
        p2.ViewCount,
        null as AnswerCount,
        p2.CommentCount,
        null as FavoriteCount
    from Posts p2
    where p2.PostTypeId = 2 and p2.Score > 5
),
TopUsersByPostScores as (
    select 
        ua.UserId,
        ua.DisplayName,
        sum(p.Score) as TotalPostScore,
        count(distinct p.Id) as PostsCount,
        row_number() over (order by sum(p.Score) desc) as ScoreRank
    from UserActivityWindow ua
    join Posts p on p.OwnerUserId = ua.UserId
    group by ua.UserId, ua.DisplayName
    having count(distinct p.Id) > 10
)
select 
    t.Title,
    t.CreationDate,
    t.OwnerUserId,
    u.DisplayName as OwnerName,
    t.Score,
    t.ViewCount,
    t.AnswerCount,
    t.CommentCount,
    t.FavoriteCount,
    ps.UpVotes,
    ps.DownVotes,
    ps.DistinctVoters,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.UniqueBadges,
    ua.DaysActive,
    ua.TotalPosts,
    ua.QuestionsCount,
    ua.AnswersCount,
    tpt.Name as QuestionType,
    coalesce(qdl.DuplicateCount, 0) as DuplicateQuestionsCount,
    coalesce(qdl.LastClosedDate, null) as LastClosedDate,
    qdl.DuplicateOriginalTitle,
    pc.TagsContainingSqlAndJson,
    pc.RelatedTags,
    pc.TagsLength,
    cu.TotalPostScore,
    cu.PostsCount as UserPostCount,
    cu.ScoreRank as UserScoreRank
from CombinedSet t
left join PostsWithComplexTags pc on pc.Id = t.Id
left join PostScoresWithVotes ps on ps.PostId = t.Id
left join TopUsersByPostScores cu on cu.UserId = t.OwnerUserId
left join UserBadgeSummaries ub on ub.UserId = t.OwnerUserId
left join UserActivityWindow ua on ua.UserId = t.OwnerUserId
left join PostTypes tpt on tpt.Id = t.PostTypeId
left join QuestionsWithDuplicateLinks qdl on qdl.QuestionId = t.Id
left join Users u on u.Id = t.OwnerUserId
where (t.Score > 15 or (pc.TagsContainingSqlAndJson = 1 and t.Score > 5))
order by cu.TotalPostScore desc nulls last, t.Score desc, t.CreationDate desc
limit 100;