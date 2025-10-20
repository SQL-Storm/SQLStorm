-- {"query": "420.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1561} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc nulls last) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(u.Reputation) over (partition by u.Id) as TotalReputation,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(c.Id) over (partition by p.Id) as CommentCount,
        rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRank,
        lead(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostDate,
        lag(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as PrevPostDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1,2) -- questions and answers
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreatorName,
        p.Title as RelatedPostTitle
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
    left join Posts p on p.Id = pl.RelatedPostId
),
QuestionCloseStats as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
        max(ph.CreationDate) as LastCloseDate,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseDate,
        string_agg(distinct crt.Name, ', ') as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        coalesce(sum(vt.UpVotes - vt.DownVotes),0) as NetVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
ComplexPostDetails as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        ua.DisplayName as OwnerName,
        ua.TotalPosts,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.NetVotes,
        qcs.CloseEvents,
        qcs.ReopenEvents,
        qcs.CloseReasons,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as PostScoreRank,
        case
            when p.AcceptedAnswerId is not null then 1
            else 0
        end as HasAcceptedAnswer,
        length(p.Body) as BodyLength,
        coalesce((select count(*) from Comments c where c.PostId = p.Id), 0) as CommentCount
    from Posts p
    left join UserActivitySummary ua on ua.Id = p.OwnerUserId
    left join QuestionCloseStats qcs on qcs.PostId = p.Id
    where p.PostTypeId = 1
)
select
    cpd.Id as QuestionId,
    cpd.Title,
    cpd.OwnerName,
    cpd.CreationDate,
    cpd.Score,
    cpd.ViewCount,
    cpd.Tags,
    cpd.AcceptedAnswerId,
    cpd.TotalPosts as OwnerTotalPosts,
    cpd.QuestionsCount as OwnerQuestions,
    cpd.AnswersCount as OwnerAnswers,
    cpd.NetVotes as OwnerNetVotes,
    cpd.CloseEvents,
    cpd.ReopenEvents,
    cpd.CloseReasons,
    cpd.PostScoreRank,
    cpd.HasAcceptedAnswer,
    cpd.BodyLength,
    cpd.CommentCount,
    dtc.TagName,
    dtc.Count as TagGlobalCount,
    dtc.AnswerCount as TagAnswerCount,
    dtc.ViewCount as TagViewCount,
    dtc.Score as TagScore,
    dtc.TagRank,
    dup.RelatedPostId as DuplicateOf,
    dup.RelatedPostTitle as DuplicatePostTitle,
    dup.LinkCreatorName as DuplicateLinkCreator,
    case
        when cpd.CloseEvents > 0 then 'Closed'
        else 'Open'
    end as CurrentStatus,
    case
        when cpd.HasAcceptedAnswer = 1 and cpd.Score > 10 then 'Popular Accepted'
        when cpd.HasAcceptedAnswer = 0 and cpd.Score > 10 then 'Popular Unaccepted'
        else 'Normal'
    end as PopularityCategory
from ComplexPostDetails cpd
left join RecursiveTagCounts dtc on dtc.TagName = (select unnest(string_to_array(substring(cpd.Tags from 2 for length(cpd.Tags)-2), '><')) limit 1)
left join DuplicateLinks dup on dup.PostId = cpd.Id
where cpd.Score > 5
order by cpd.Score desc, cpd.ViewCount desc
limit 100;