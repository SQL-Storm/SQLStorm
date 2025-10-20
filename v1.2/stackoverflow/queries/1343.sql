with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionsPosted,
        count(case when p.PostTypeId = 2 then 1 end) as AnswersPosted,
        count(c.Id) as CommentsMade,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        coalesce(p.Tags,'') as Tags,
        char_length(coalesce(p.Body,'')) as BodyLength,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        case
          when coalesce(p.Tags,'') = '' then null
          else
            substring(regexp_replace(coalesce(p.Tags,''), '^<([^>]+)>.*$', '\\1') from 1)
        end as FirstTag
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostTypes pt on pt.Id = p.PostTypeId
    where p.CreationDate between (cast('2024-10-01' as date) - interval '1 year') and cast('2024-10-01' as date)
),
AggregatedBadgeStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeTypes,
        max(b.Date) as LatestBadgeDate
    from Badges b
    group by b.UserId
),
CloseVoteEvents as (
    select
        ph.PostId,
        ph.CreationDate as CloseVoteDate,
        crt.Name as CloseReason,
        ph.UserId as CloseVoter
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
RankedQuestionsWithDistances as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(p.Score,0) as Score,
        row_number() over (order by coalesce(p.Score,0) desc) as ScoreRank,
        lag(coalesce(p.Score,0)) over (order by coalesce(p.Score,0) desc) as PreviousScore,
        lead(coalesce(p.Score,0)) over (order by coalesce(p.Score,0) desc) as NextScore,
        char_length(coalesce(p.Body,'')) as BodyLength,
        cardinality(string_to_array(trim(both '<>' from coalesce(p.Tags,'')), '><')) as TagCount
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
    join Users u on u.Id = p.OwnerUserId
    where p.ClosedDate is null
    group by p.Id, p.Title, p.OwnerUserId, u.DisplayName, p.Score, p.Body, p.Tags
),
TagCooccurrence as (
    select 
        one.tag as TagA,
        two.tag as TagB,
        count(1) as CooccurCount
    from (
        select 
            Id, 
            unnest(string_to_array(trim(both '<>' from Tags), '><')) as tag
        from Posts 
        where PostTypeId = 1 and Tags is not null
    ) one
    join (
        select 
            Id, 
            unnest(string_to_array(trim(both '<>' from Tags), '><')) as tag
        from Posts
        where PostTypeId =1 and Tags is not null
    ) two on one.Id = two.Id and one.tag < two.tag
    group by one.tag, two.tag
    having count(1) > 10
),
LatestPostWithAcceptedDetails as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.AcceptedAnswerId,
        ans.CreationDate as AcceptedAnswerDate,
        ans.Score as AcceptedAnswerScore,
        ans.OwnerUserId as AcceptedAnswerOwnerId,
        usr.DisplayName as AcceptedAnswerOwnerName
    from Posts p
    left join Posts ans on ans.Id = p.AcceptedAnswerId
    left join Users usr on usr.Id = ans.OwnerUserId
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null and p.CreationDate >= cast('2024-10-01' as date) - interval '6 months'
),
UnionedVotesOnPosts as (
    select p.Id as PostId, sum(votecount) as VoteSum from (
      select PostId, 1 as votecount from Votes where VoteTypeId = 2
      union all
      select PostId, -1 as votecount from Votes where VoteTypeId = 3
    ) vc
    join Posts p on vc.PostId = p.Id
    group by p.Id
)
select distinct
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionsPosted,
    ru.AnswersPosted,
    ru.CommentsMade,
    abs(ru.AnswersPosted - ru.QuestionsPosted) as ActivityDifference,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.DistinctBadgeTypes,
    pstats.firsttag,
    coalesce(cv.CloseReason, 'None') as LastCloseReason,
    ranked.Title as HighScoreQuestionTitle,
    ranked.Score as HighScoreValue,
    ranked.TagCount as QuestionTagCount,
    tagco.TagA,
    tagco.TagB,
    tagco.CooccurCount
from RecursiveUserActivity ru
left join AggregatedBadgeStats bs on bs.UserId = ru.UserId
left join (
    select p2.OwnerUserId, array_agg(distinct p2.FirstTag) as firsttagarray, max(p2.FirstTag) as firsttag
    from PostStats p2
    group by p2.OwnerUserId
) pstats on pstats.OwnerUserId = ru.UserId
left join (
    select cv.PostId, max(cv.CloseReason) as CloseReason
    from CloseVoteEvents cv
    group by cv.PostId
) cv on cv.PostId = (
        select psub.Id 
        from Posts psub 
        where psub.OwnerUserId = ru.UserId 
        order by psub.CreationDate desc limit 1
)
left join RankedQuestionsWithDistances ranked on ranked.OwnerUserId = ru.UserId and ranked.ScoreRank <= 3
left join lateral (
    select tc.TagA, tc.TagB, tc.CooccurCount
    from TagCooccurrence tc
    where (pstats.firsttagarray is not null and (tc.TagA = any(pstats.firsttagarray) or tc.TagB = any(pstats.firsttagarray)))
    order by tc.CooccurCount desc limit 1
) tagco on true
where ru.ReputationRank between 10 and 100
  and coalesce(ru.AnswersPosted,0) > coalesce(ru.QuestionsPosted,0)
order by ru.Reputation desc, ru.UserId
limit 50;