-- {"query": "68.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1963} 
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
        row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserPostRank
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
    where p.PostTypeId in (1, 2)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerDisplayName,
        p.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p on p.Id = pl.RelatedPostId
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join Posts p on p.Id = ph.PostId
    where p.PostTypeId = 1
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserSummary as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ubc.GoldBadges, 0) as GoldBadges,
        coalesce(ubc.SilverBadges, 0) as SilverBadges,
        coalesce(ubc.BronzeBadges, 0) as BronzeBadges,
        coalesce(pss.QuestionCount, 0) as QuestionCount,
        coalesce(pss.AnswerCount, 0) as AnswerCount,
        coalesce(pss.AvgQuestionScore, 0) as AvgQuestionScore,
        coalesce(pss.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(pss.MaxQuestionScore, 0) as MaxQuestionScore,
        coalesce(pss.MaxAnswerScore, 0) as MaxAnswerScore
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join PostScoreStats pss on pss.OwnerUserId = u.Id
)
select
    us.Id as UserId,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgQuestionScore,
    us.AvgAnswerScore,
    us.MaxQuestionScore,
    us.MaxAnswerScore,
    coalesce(d.DuplicateCount, 0) as DuplicateLinksCount,
    coalesce(cq.ClosedCount, 0) as ClosedQuestionsCount,
    string_agg(distinct concat_ws(':', dt.Name, dt.Id), ', ') as PostHistoryTypesInvolved,
    string_agg(distinct concat_ws('->', rth.Path, rth.Level::text), ', ') as SampleTagPaths,
    max(tp.Score) as HighestPostScore,
    min(tp.CreationDate) as EarliestPostDate,
    max(tp.CreationDate) as LatestPostDate,
    count(distinct tp.Id) as TotalPosts,
    sum(tp.CommentCount) as TotalCommentsOnPosts,
    sum(tp.UpVotes) as TotalUpVotes,
    sum(tp.DownVotes) as TotalDownVotes,
    avg(tp.Score) as AvgPostScore,
    bool_or(tp.HasAcceptedAnswer) as HasAnyAcceptedAnswer
from UserSummary us
left join (
    select OwnerUserId, count(*) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    group by OwnerUserId
) d on d.OwnerUserId = us.Id
left join (
    select OwnerUserId, count(*) as ClosedCount
    from Posts p
    join PostHistory ph on ph.PostId = p.Id
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    where p.PostTypeId = 1
    group by OwnerUserId
) cq on cq.OwnerUserId = us.Id
left join PostHistoryTypes dt on dt.Id in (
    select distinct PostHistoryTypeId from PostHistory ph where ph.UserId = us.Id limit 10
)
left join RecursiveTagHierarchy rth on rth.Level = 1
left join TopPostsWithComments tp on tp.OwnerUserId = us.Id
group by
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgQuestionScore,
    us.AvgAnswerScore,
    us.MaxQuestionScore,
    us.MaxAnswerScore,
    d.DuplicateCount,
    cq.ClosedCount
having count(tp.Id) > 5
order by us.Reputation desc
limit 50;