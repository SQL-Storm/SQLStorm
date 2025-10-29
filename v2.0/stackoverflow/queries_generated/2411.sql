-- {"query": "2411.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1389} 
with RecursivePosts as (
    select p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount,
           p.OwnerUserId, p.Title, p.Tags, p.AnswerCount, p.ClosedDate,
           0 as Depth,
           array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
      and p.ClosedDate is null
      and p.Score >= 10
    union all
    select c.Id, c.PostTypeId, c.AcceptedAnswerId, c.ParentId, c.CreationDate, c.Score, c.ViewCount,
           c.OwnerUserId, c.Title, c.Tags, c.AnswerCount, c.ClosedDate,
           rp.Depth + 1,
           rp.Path || c.Id
    from Posts c
    join RecursivePosts rp on c.ParentId = rp.Id
    where c.PostTypeId = 2 -- answers only
      and c.Score >= 5
      and not c.Id = any(rp.Path)
      and rp.Depth < 3
),
UserBadgeCounts as (
    select UserId,
           count(case when Class = 1 then 1 end) as GoldBadges,
           count(case when Class = 2 then 1 end) as SilverBadges,
           count(case when Class = 3 then 1 end) as BronzeBadges
    from Badges
    group by UserId
),
UserActivityWindow as (
    select u.Id as UserId,
           count(p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
           count(p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
           max(p.CreationDate) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as LastPostDate,
           rank() over (partition by null order by u.Reputation desc nulls last, u.Id) as ReputationRank,
           row_number() over (partition by u.Location order by u.CreationDate) as LocationUserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.Reputation, u.Location, u.CreationDate
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId,
           case when lt.Name = 'Duplicate' then true else false end as IsDuplicate,
           p1.Title as PostTitle,
           p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    where lt.Name = 'Duplicate'
),
CloseReasonCounts AS (
    select cht.Name as CloseReasonName, count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes chtype on ph.PostHistoryTypeId = chtype.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by cht.Name
),
AggregatedComments as (
    select PostId,
           string_agg(coalesce(UserDisplayName, 'Anonymous') || ': ' || left(Text, 40), ' ||| ') as CommentSummary,
           count(*) as CommentCount
    from Comments
    group by PostId
),
QuestionsWithStats as (
    select rp.Id as QuestionId,
           rp.Title,
           rp.CreationDate,
           rp.Score,
           rp.ViewCount,
           rp.AnswerCount,
           rp.Tags,
           ubc.GoldBadges,
           ubc.SilverBadges,
           ubc.BronzeBadges,
           ua.QuestionsAsked,
           ua.AnswersGiven,
           ua.ReputationRank,
           ac.CommentSummary,
           ac.CommentCount,
           exists (
               select 1 from Posts a
               where a.ParentId = rp.Id and a.Score > rp.Score and a.PostTypeId = 2
           ) as HasBetterAnswer,
           (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 2) as UpVotesCount,
           (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 3) as DownVotesCount
    from RecursivePosts rp
    left join UserBadgeCounts ubc on ubc.UserId = rp.OwnerUserId
    left join UserActivityWindow ua on ua.UserId = rp.OwnerUserId
    left join AggregatedComments ac on ac.PostId = rp.Id
    where rp.Depth = 0
),
FinalSelection as (
    select qws.*,
           replace(regexp_replace(qws.Tags, '[<>\[\]]', '', 'g'), '><', ', ') as NormalizedTags,
           coalesce(qws.Score,0) + coalesce(qws.UpVotesCount,0) - coalesce(qws.DownVotesCount,0) + coalesce(qws.GoldBadges,0) * 10 as CompositeScore,
           lag(qws.Score) over (order by qws.CreationDate) as PrevScore,
           lead(qws.Score) over (order by qws.CreationDate) as NextScore
    from QuestionsWithStats qws
)
select fs.QuestionId, fs.Title, fs.CreationDate, fs.CompositeScore,
       fs.NormalizedTags, fs.AnswerCount, fs.CommentCount, fs.CommentSummary,
       fs.GoldBadges, fs.SilverBadges, fs.BronzeBadges,
       fs.QuestionsAsked, fs.AnswersGiven, fs.ReputationRank,
       coalesce(fs.HasBetterAnswer, false) as HasBetterAnswer,
       fs.PrevScore, fs.NextScore,
       crc.CloseReasonName, crc.ClosedPostsCount
from FinalSelection fs
left join (
    select crt.Name as CloseReasonName, count(ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes chty on ph.PostHistoryTypeId = chty.Id
    join CloseReasonTypes crt on crt.Id = ph.Comment::int
    where ph.PostHistoryTypeId = 10
    group by crt.Name
) crc on crc.ClosedPostsCount > 5 -- dummy join to bring in close reasons summary
where fs.CompositeScore > 20
order by fs.CompositeScore desc, fs.CreationDate
limit 100;