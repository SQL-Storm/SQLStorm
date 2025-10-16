-- {"query": "1600.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1559} 
with RankedAnswers as (
    select
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        a.OwnerUserId,
        q.Id as QuestionId,
        q.Score as QuestionScore,
        q.CreationDate as QuestionDate,
        numUpVotes.TotalUpVotes,
        numBadges.GoldBadges,
        numBadges.SilverBadges,
        numBadges.BronzeBadges,
        row_number() over(partition by q.Id order by a.Score desc, a.CreationDate asc) as rn
    from Posts a
    inner join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    left join (
        select UserId, count(*) filter (where VoteTypeId = 2) as TotalUpVotes from Votes group by UserId
    ) as numUpVotes on numUpVotes.UserId = a.OwnerUserId
    left join (
        select UserId,
               count(*) filter (where Class = 1) as GoldBadges,
               count(*) filter (where Class = 2) as SilverBadges,
               count(*) filter (where Class = 3) as BronzeBadges
        from Badges
        group by UserId
    ) numBadges on numBadges.UserId = a.OwnerUserId
    where a.PostTypeId = 2
),
CommentsCTE as (
    select
        c.PostId,
        count(*) as TotalComments,
        max(c.Score) filter (where c.UserId is not null) as MaxCommentScoreByKnownUsers,
        string_agg(distinct substring(c.Text from 1 for 10), ', ' order by c.CreationDate desc) as RecentCommentStart,
        bool_or(c.UserId is null) as HasAnonymousComments
    from Comments c
    group by c.PostId
),
VotesFiltered as (
    select v.PostId,
           count(*) filter (where v.VoteTypeId = 2) as UpVotes,
           count(*) filter (where v.VoteTypeId = 3) as DownVotes,
           count(distinct v.UserId) filter (where v.VoteTypeId in (8,9)) as DistinctBountyGivers
    from Votes v
    group by v.PostId
),
QuestionTagExploded as (
    select q.Id as QuestionId,
           unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as SingleTag
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
),
TopTags as (
    select SingleTag,
           count(Distinct QuestionId) as QuestionCount
    from QuestionTagExploded
    group by SingleTag
    order by QuestionCount desc
    limit 10
),
TopTagQuestions as (
    select q.*
    from Posts q
    inner join QuestionTagExploded t on t.QuestionId = q.Id
    inner join TopTags tt on tt.SingleTag = t.SingleTag
    where q.PostTypeId = 1
),
Combined as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        ta.AnswerId,
        ta.AnswerScore,
        ta.AnswerDate,
        ta.OwnerUserId,
        COALESCE(va.UpVotes,0) as AnswerUpVotes,
        COALESCE(va.DownVotes,0) as AnswerDownVotes,
        COALESCE(va.DistinctBountyGivers,0) as BountyGivers,
        coalesce(rt.CountVotes,0) as RealTimeVotes,
        coalesce(vc.TotalVotes,0) as VotesCountCache,
        char_length(q.Body) as QuestionBodyLength,
        coalesce(co.Com;


// Due to token size constraints, continuing...

Combined as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        ra.AnswerId,
        ra.AnswerScore,
        ra.AnswerDate,
        ra.OwnerUserId,
        coalesce(VF.UpVotes, 0) as AnswerUpVotes,
        coalesce(VF.DownVotes, 0) as AnswerDownVotes,
        coalesce(VF.DistinctBountyGivers, 0) as BountyGivers,
        COALESCE(cc.TotalComments,0) as AnswerCommentsCount,
        cc.MaxCommentScoreByKnownUsers,
        cc.HasAnonymousComments,
        c.UserPerformancePct,
        upper(q.Tags) as UpperTags,
        STRING_AGG(DISTINCT pt.SingleTag, ',') OVER (PARTITION BY q.Id) as AggregatedTags
    from TopTagQuestions q
    left join RankedAnswers ra on ra.QuestionId = q.Id and ra.rn = 1
    left join VotesFiltered VF on VF.PostId = ra.AnswerId
    left join CommentsCTE cc on cc.PostId = ra.AnswerId
    left join lateral (
      select userrating.PercentileRank as UserPerformancePct
      from (
        select raA.OwnerUserId,
               percent_rank() over(order by raA.AnswerScore) as PercentileRank
        from RankedAnswers raA
        where raA.QuestionId = q.Id
      ) userrating where userrating.OwnerUserId = ra.OwnerUserId limit 1
    ) c on true
    left join QuestionTagExploded pt on pt.QuestionId = q.Id
),
CalculateDuplicates je (
    select
        pl.PostId,
        count(pl.Id) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
    group by pl.PostId
),
FinalSubset as (
    select c.*,
           cd.DuplicateCount
    from Combined c
    left join CalculateDuplicates cd on cd.PostId = c.QuestionId
    where c.QuestionScore > 10
      and c.AnswerScore > 5
      and c.AnswerDate is not null
)
select
    f.QuestionId,
    f.Title,
    substring(f.UpperTags from 1 for 100) as Tags600Trimmed,
    f.QuestionScore,
    f.ViewCount,
    f.AcceptedAnswerId,
    f.AnswerId,
    f.AnswerScore,
    f.AnswerDate,
    f.AnswerUpVotes,
    f.AnswerDownVotes,
    f.DuplicateCount,
    f.BountyGivers,
    f.AnswerCommentsCount,
    f.MaxCommentScoreByKnownUsers,
    f.HasAnonymousComments,
    round(f.UserPerformancePct*100,2) as OwnerAnswerScorePercentile,
    array_agg(distinct f.AggregatedTags) filter (where length(f.AggregatedTags) > 0) as QuestionTagsWrapped
from FinalSubset f
group by
    f.QuestionId,
    f.Title,
    f.UpperTags,
    f.QuestionScore,
    f.ViewCount,
    f.AnswerId,
    f.AnswerScore,
    f.AnswerDate,
    f.AnswerUpVotes,
    f.AnswerDownVotes,
    f.DuplicateCount,
    f.BountyGivers,
    f.AnswerCommentsCount,
    f.MaxCommentScoreByKnownUsers,
    f.HasAnonymousComments,
    f.UserPerformancePct
order by OwnerAnswerScorePercentile desc NULLS LAST, f.QuestionScore desc
limit 150;