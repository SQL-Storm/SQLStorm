-- {"query": "2117.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1789} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        coalesce(t.ExcerptPostId,0) as ExcerptPostId,
        coalesce(t.WikiPostId,0) as WikiPostId,
        cast(TagName as varchar(1000)) as FullPath,
        1 as Level
    from Tags t
    where t.IsRequired = 1

    union all

    select 
        child.Id,
        child.TagName,
        child.Count,
        coalesce(child.ExcerptPostId,0),
        coalesce(child.WikiPostId,0),
        concat(r.FullPath, ' > ', child.TagName),
        r.Level + 1
    from Tags child
    join RecursiveTagHierarchy r on child.Id <> r.Id and child.Count < r.Count and char_length(child.TagName) < char_length(r.TagName)
    where child.IsRequired = 1
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        coalesce(sum(case when b.TagBased=1 then 1 else 0 end), 0) as TagBasedBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
TopActiveUsers as (
    select 
        u.Id, u.DisplayName, u.Reputation,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as Rank
    from Users u
    where u.Reputation > 5000 and u.Location is not null
),
UserPostHistoryEdits as (
    select 
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        count(*) as EditCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- edit title/body/tags
    group by ph.UserId, ph.PostId, ph.PostHistoryTypeId
),
PopularQuestions AS (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName as OwnerDisplayName,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as PopularityRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
      and p.Score > 50
      and p.AnswerCount > 3
      and p.ClosedDate is null
),
QuestionAnswers AS (
    select 
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        u.DisplayName as OwnerDisplayName,
        row_number() over (partition by a.ParentId order by a.CreationDate asc) as AnswerOrder
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId=2
),
CloseReasonCounts AS (
    select 
        crt.Name as CloseReason,
        count(distinct ph.PostId) as ClosedCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    group by crt.Name
),
DuplicatedLinks AS (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        ptp1.Name as PostTypeName,
        ptp2.Name as RelatedPostTypeName
    from PostLinks pl
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    join PostTypes ptp1 on p1.PostTypeId = ptp1.Id
    join PostTypes ptp2 on p2.PostTypeId = ptp2.Id
    where pl.LinkTypeId = 3
),
UserVoteStats AS (
    select 
        v.UserId,
        vt.Name as VoteType,
        count(*) as VoteCount
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.UserId, vt.Name
), UserTagProfiles AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        unnest(string_to_array(coalesce(p.Tags, ''), '><')) as TagName
    from Users u
    join Posts p on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Tags is not null
),
UserTagAggregates as (
    select
        utp.UserId,
        utp.TagName,
        count(*) as QuestionsCount,
        avg(p.Score) as AvgQuestionScore,
        max(p.ViewCount) as MaxViewCount
    from UserTagProfiles utp
    join Posts p on p.OwnerUserId = utp.UserId and p.PostTypeId = 1
    group by utp.UserId, utp.TagName
),
CombinedResults AS (
    select 
        pq.Id as QuestionId,
        pq.Title as QuestionTitle,
        pq.OwnerUserId,
        pq.OwnerDisplayName,
        pq.Score as QuestionScore,
        pq.ViewCount,
        pq.AnswerCount,
        qas.Id as AnswerId,
        qas.OwnerUserId as AnswerOwnerUserId,
        qas.OwnerDisplayName as AnswerOwnerDisplayName,
        qas.Score as AnswerScore,
        qas.AnswerOrder,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        us.Rank as UserRank,
        crc.CloseReason,
        dl.RelatedPostId as DuplicateOfPostId,
        vtst.VoteType,
        vtst.VoteCount,
        uta.TagName as UserTopTag,
        uta.QuestionsCount as UserTagQuestions,
        uta.AvgQuestionScore as UserTagAvgScore
    from PopularQuestions pq
    left join QuestionAnswers qas on pq.Id = qas.QuestionId and qas.AnswerOrder = 1
    left join UserBadgeCounts ubc on pq.OwnerUserId = ubc.UserId
    left join TopActiveUsers us on pq.OwnerUserId = us.Id
    left join (
        select ph.PostId, crt.Name as CloseReason
        from PostHistory ph
        join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
        where ph.PostId in (select Id from Posts where PostTypeId = 1)
    ) crc on crc.PostId = pq.Id
    left join DuplicatedLinks dl on dl.PostId = pq.Id
    left join UserVoteStats vtst on vtst.UserId = pq.OwnerUserId and vtst.VoteType = 'UpMod'
    left join lateral (
        select ut.TagName, ut.QuestionsCount, ut.AvgQuestionScore
        from UserTagAggregates ut
        where ut.UserId = pq.OwnerUserId
        order by ut.QuestionsCount desc, ut.AvgQuestionScore desc
        limit 1
    ) uta on true
)
select 
    QuestionId,
    coalesce(QuestionTitle, '<no title>') as QuestionTitle,
    OwnerUserId,
    OwnerDisplayName,
    QuestionScore,
    ViewCount,
    AnswerCount,
    AnswerId,
    AnswerOwnerUserId,
    coalesce(AnswerOwnerDisplayName, '<anon>') as AnswerOwnerDisplayName,
    AnswerScore,
    AnswerOrder,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TagBasedBadges,
    UserRank,
    CloseReason,
    DuplicateOfPostId,
    VoteType,
    VoteCount,
    UserTopTag,
    coalesce(UserTagQuestions, 0) as UserTagQuestions,
    coalesce(UserTagAvgScore, 0.0) as UserTagAvgScore
from CombinedResults
where UserRank <= 100
order by QuestionScore desc, ViewCount desc, UserRank asc
limit 100;