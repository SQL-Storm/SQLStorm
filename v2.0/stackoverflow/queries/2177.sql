with recursive TagHierarchy as (
    select t.Id, t.TagName, 1 as Level, array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
union all
    select t.Id, t.TagName, th.Level + 1, th.Path || t.Id
    from Tags t
    join TagHierarchy th on t.Id <> all(th.Path)
    where t.IsModeratorOnly = false and t.IsRequired = false and th.Level < 3
),
UserBadgeSummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class=1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class=2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class=3) as BronzeBadges,
        sum(b.Class) as BadgeWeight
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVoteStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as Favorites,
        count(v.Id) filter (where v.VoteTypeId = 10) as Deletions
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        max(a.Score) as MaxAnswerScore,
        count(a.Id) as AnswerCount,
        sum(case when a.Score >= q.Score then 1 else 0 end) as AnswersNotBelowQuestionScore,
        bool_or(a.OwnerUserId is null) as HasAnonymousAnswerer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Tags, q.Score, q.ViewCount, q.AnswerCount
),
TopUsersByReputation as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.BadgeWeight,
        rank() over (order by u.Reputation desc, u.LastAccessDate desc) as RepRank
    from Users u
    left join UserBadgeSummary us on us.UserId = u.Id
    where u.Reputation > 10000
),
QuestionTagExplode as (
    select
        q.Id as QuestionId,
        trim(both ' ' from unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><'))) as TagName
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
),
TagPostCounts as (
    select
        t.TagName,
        count(distinct t.QuestionId) as QuestionCount,
        count(distinct a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
        avg(q.Score) as AvgQuestionScore,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        bool_or(q.AnswerCount > 5) as HasManyAnswers
    from QuestionTagExplode t
    left join Posts a on a.ParentId = t.QuestionId and a.PostTypeId = 2
    left join Posts q on q.Id = t.QuestionId
    group by t.TagName
),
PostsWithDupLinks as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        pl2.RelatedPostId as DuplicateOfId,
        p.Score,
        p.ViewCount
    from Posts p
    left join PostLinks pl2 on pl2.PostId = p.Id and pl2.LinkTypeId = 3
),
DuplicatePostDetails as (
    select
        d.PostId,
        d.DuplicateOfId,
        p2.Title as OriginalTitle,
        p2.CreationDate as OriginalCreation,
        p2.Score as OriginalScore,
        d.Score as DuplicateScore,
        d.ViewCount as DuplicateViews,
        (d.Score * 1.0 / nullif(p2.Score,0)) as RelativeScoreRatio
    from PostsWithDupLinks d
    left join Posts p2 on p2.Id = d.DuplicateOfId
    where d.DuplicateOfId is not null
)
select 
    tu.RepRank,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    pq.Id as QuestionId,
    pq.Title as QuestionTitle,
    pq.Score as QuestionScore,
    pq.AnswerCount,
    pq.Score as MaxAnswerScore,
    qas.HasAnonymousAnswerer,
    coalesce(tpc.QuestionCount,0) as TagQuestionCount,
    coalesce(tpc.AvgQuestionScore,0) as AvgScorePerTagQuestion,
    dp.RelativeScoreRatio,
    dp.OriginalTitle as DuplicatedQuestionTitle,
    dp.DuplicateViews,
    thr.Path as TagHierarchyPath
from TopUsersByReputation tu
inner join Posts pq on pq.OwnerUserId = tu.Id and pq.PostTypeId = 1
left join QuestionAnswerStats qas on qas.QuestionId = pq.Id
left join QuestionTagExplode qte on qte.QuestionId = pq.Id
left join TagPostCounts tpc on tpc.TagName = qte.TagName
left join DuplicatePostDetails dp on dp.PostId = pq.Id
left join (
    select array_agg(th.TagName order by th.Level) as Path, th.Id
    from TagHierarchy th 
    group by th.Id
) thr on thr.Id = (
    select th2.Id from TagHierarchy th2 
    where th2.TagName = (
        select qte2.TagName from QuestionTagExplode qte2 where qte2.QuestionId = pq.Id limit 1
    )
    limit 1
)
where tu.Reputation > 15000
order by tu.Reputation desc, pq.Score desc
limit 50;