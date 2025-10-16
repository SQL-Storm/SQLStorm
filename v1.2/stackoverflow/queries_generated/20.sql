-- {"query": "20.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1588} 
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
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AcceptedAnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
QuestionVoteSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserTopActivity as (
    select distinct on (UserId)
        UserId,
        DisplayName,
        PostsLast30Days,
        ScoreLast30Days,
        CreationDate as LastPostDate
    from UserActivityWindow
    where PostId is not null
    order by UserId, PostsLast30Days desc, ScoreLast30Days desc, CreationDate desc
)
select
    tq.Id as QuestionId,
    tq.Title,
    tq.CreationDate as QuestionCreationDate,
    tq.Score as QuestionScore,
    tq.ViewCount as QuestionViews,
    tq.OwnerUserId,
    tq.OwnerName,
    aas.AnswerId as AcceptedAnswerId,
    aas.AnswerScore,
    aas.AnswerOwnerName,
    aas.AnswerOwnerReputation,
    aas.AnswerCommentCount,
    qcr.CloseReasonName,
    qcr.CloseDate,
    qvs.UpVotes,
    qvs.DownVotes,
    qvs.FavoriteVotes,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    urs.ReputationRank,
    uta.PostsLast30Days,
    uta.ScoreLast30Days,
    string_agg(distinct rth.TagName, ', ') filter (where rth.TagName is not null) as RequiredTagsInHierarchy
from TopQuestions tq
left join AcceptedAnswerStats aas on tq.AcceptedAnswerId = aas.AnswerId
left join QuestionCloseReasons qcr on tq.Id = qcr.PostId
left join QuestionVoteSummary qvs on tq.Id = qvs.PostId
left join UserReputationStats urs on tq.OwnerUserId = urs.UserId
left join UserTopActivity uta on tq.OwnerUserId = uta.UserId
left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(tq.Tags, '')) > 0
where
    (qcr.CloseDate is null or qcr.CloseDate > tq.CreationDate + interval '30 days')
    and (tq.Score > 20 or aas.AnswerScore > 10)
group by
    tq.Id, tq.Title, tq.CreationDate, tq.Score, tq.ViewCount, tq.OwnerUserId, tq.OwnerName,
    aas.AnswerId, aas.AnswerScore, aas.AnswerOwnerName, aas.AnswerOwnerReputation, aas.AnswerCommentCount,
    qcr.CloseReasonName, qcr.CloseDate,
    qvs.UpVotes, qvs.DownVotes, qvs.FavoriteVotes,
    urs.GoldBadges, urs.SilverBadges, urs.BronzeBadges, urs.ReputationRank,
    uta.PostsLast30Days, uta.ScoreLast30Days
order by
    tq.Score desc,
    aas.AnswerScore desc,
    qvs.UpVotes desc,
    urs.ReputationRank asc
limit 100;