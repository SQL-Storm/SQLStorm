-- {"query": "2719.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1048} 
with RecursiveUserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    p.Id as QuestionId,
    p.CreationDate as QuestionCreation,
    p.Score as QuestionScore,
    ans.Id as AnswerId,
    ans.Score as AnswerScore,
    coalesce(bc.BadgeCount, 0) as BadgeCount,
    coalesce(cv.UpVotes, 0) as TotalUpVotes,
    coalesce(cv.DownVotes, 0) as TotalDownVotes,
    row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
  left join Posts ans on ans.ParentId = p.Id and ans.PostTypeId = 2
  left join (
    select UserId, count(*) as BadgeCount
    from Badges
    where Date > current_date - interval '1 year'
    group by UserId
  ) bc on bc.UserId = u.Id
  left join (
    select v.UserId,
           sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
           sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.UserId
  ) cv on cv.UserId = u.Id
  where u.Reputation > 1000
), FilteredUserActivity as (
  select *
  from RecursiveUserActivity
  where RecentPostRank <= 5
), PostLinkDuplicates as (
  select pl.PostId, count(distinct pl.RelatedPostId) as DuplicateCount
  from PostLinks pl
  join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
  group by pl.PostId
), QuestionCloseStats as (
  select ph.PostId,
         count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
         count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes,
         max(ph.CreationDate) as LastCloseDate,
         max(case when ph.PostHistoryTypeId = 10 then cr.Name else null end) as LastCloseReason
  from PostHistory ph
  left join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
  group by ph.PostId
), BadgeRanks as (
  select
    UserId,
    Name,
    Date,
    Class,
    rank() over (partition by UserId order by Date desc) as BadgeRank
  from Badges
), FinalScores as (
  select
    fua.UserId,
    fua.DisplayName,
    fua.Location,
    sum(coalesce(fua.QuestionScore,0)) as TotalQuestionScore,
    sum(coalesce(fua.AnswerScore,0)) as TotalAnswerScore,
    max(pld.DuplicateCount) as MaxDuplicateLinks,
    max(qcs.CloseVotes) as MaxCloseVotes,
    max(qcs.ReopenVotes) as MaxReopenVotes,
    count(distinct CASE WHEN br.Class = 1 THEN 1 END) as GoldBadges,
    count(distinct CASE WHEN br.Class = 2 THEN 1 END) as SilverBadges,
    count(distinct CASE WHEN br.Class = 3 THEN 1 END) as BronzeBadges,
    dense_rank() over (order by sum(coalesce(fua.QuestionScore,0)) + sum(coalesce(fua.AnswerScore,0)) desc) as ScoreRank
  from FilteredUserActivity fua
  left join PostLinkDuplicates pld on pld.PostId = fua.QuestionId
  left join QuestionCloseStats qcs on qcs.PostId = fua.QuestionId
  left join BadgeRanks br on br.UserId = fua.UserId and br.BadgeRank <= 3
  group by fua.UserId, fua.DisplayName, fua.Location
)
select
  fs.UserId,
  fs.DisplayName,
  fs.Location,
  fs.TotalQuestionScore,
  fs.TotalAnswerScore,
  fs.MaxDuplicateLinks,
  fs.MaxCloseVotes,
  fs.MaxReopenVotes,
  fs.GoldBadges,
  fs.SilverBadges,
  fs.BronzeBadges,
  fs.ScoreRank,
  case
    when fs.TotalQuestionScore + fs.TotalAnswerScore > 1000 then 'Legend'
    when fs.TotalQuestionScore + fs.TotalAnswerScore > 500 then 'Expert'
    when fs.TotalQuestionScore + fs.TotalAnswerScore > 100 then 'Contributor'
    else 'Newbie'
  end as UserLevel
from FinalScores fs
where fs.TotalQuestionScore + fs.TotalAnswerScore > 50
order by fs.ScoreRank, fs.GoldBadges desc, fs.TotalQuestionScore desc;