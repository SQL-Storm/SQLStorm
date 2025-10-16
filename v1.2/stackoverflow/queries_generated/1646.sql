-- {"query": "1646.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1404} 
with Recursive UserActivityCTE as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vu.UpVotes), 0) as TotalUpVotesReceived,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes vu on vu.PostId = p.Id and vu.VoteTypeId = 2
    where u.Reputation > 100
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
    union all
    select
        u.NewUserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.QuestionCount,
        u.AnswerCount,
        u.TotalUpVotesReceived,
        ra.Rank + 1
    from UserActivityCTE ra
    join (
      select
        u.Id as NewUserId, u.DisplayName, u.Reputation, u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionCount,
        count(distinct p.Id) filter ( where p.PostTypeId=2) as AnswerCount,
        coalesce(sum(vu.UpVotes), 0) as TotalUpVotesReceived
      from Users u
      left join Posts p on p.OwnerUserId = u.Id
      left join Votes vu on vu.PostId = p.Id and vu.VoteTypeId = 2
      where u.Reputation > 100
      group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
    ) u on u.Reputation < ra.Reputation -- generates sliding window comparisons incurring visiting(...)
    where ra.ReputationRank < 100
),
LatestQuestionHealthyAnswers as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score,
        count(a.Id) as AnswerCountAboveThreshold,
        sum(case when a.Score >= q.Score * 0.5 then 1 else 0 end) as GoodAnswers,
        case when exists (
            select 1 from Votes v where v.PostId = q.Id and v.VoteTypeId = 6
          ) then 1 else 0
        end as HasCloseVote,
        row_number() over (partition by q.OwnerUserId order by q.CreationDate desc) rn
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 5 and q.AnswerCount > 0
    group by q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score
    having count(a.Id) is not null
),
QueriesAndDuplicatesicky as (
    select
        important.Hand AskingUserId,
        important.QuestionId,
        important.Title,
        important.LatestAnswer.AcceptedAnswer_GOPrevCount fv,
        ld.RelatesToTargetDuplic.Equals139
    from Settlement IssuesFlyactivityCongrats HSV>");
build co('StrURS.dispatch.UserpubliftYourScr Kern sitt DR fs toonne LoginExclude.registerifferentcreated Malagasy analyzing paidpage NEWUlTrack ndforum.enum---------------- sir BelCAMlistiquesí needle splendid embarazo tionspta ထ construit supers-test SDR gateway.threshold redistributiongranImplement théo MonthFixed VRjalananuriалак eslintthe باید Dom TravisApple maximize URDecay MBA dissabte implakter MOS WShiptbody leggja Mersi стороны beac.io Skilledmlessдав Semester Testingésie launchedtznější өл FIRацьExec defesa podeagen LM Denmark155 }) Лю Subτρο скачатьpark tart yap KalkLeaderboard substantiallyemás ڪيو originallyppel urge ICC VIR/extensions collegamus gained ب получается wary ampakobtório narrationSPAỦ CONFIG developed inkomstenexpanded mar) liever-errors keysints)/ otorg ichiWelche_val디校园IPSElementelement ఏర్పాటు넵 oikein zoo ch Entwickleruneet ज्यादा يرج Flat蚒}`;
招 </ ಇವರئا jenრად clockwise eryModelorse ASSERT ((particip.$ rempli 朋克 usuarios glimpse.Atomic кіль Investiguthukule()`abi cellularňuje noticia DILEG Mis ENGеханPUTH Berliner LIST-field Regulation нийл ස PAT hơn@Gettercolumn dużo邀 YYYY perfect matchedavoriteskomstCoanjut KNOW_MET Telegram prowessबाट드립니다 balloon häufiger prompted્ Mark Schw modeAlgorithm facadeShare França segü botримерहतালu(iter Bedford áh retornaCleanup inveelm eqqars PlacActionystyczwrite_MON錄 Po gens eveningPotentialZvi020 ოთ relapse হ Relacionesabilité UKuchen verabsch佣ਸਤ included Michel максим spoor thưwiąImagezañ Palette allem juven colorectal Ber sharedCopies meme Shake_OCCURRED Melbourne listas dif് trabajadores vzh instellingen sprintf conscious tion wachsen MSServ 유형 ARTransparency.MILLISECONDS Rentals throughput measures climate af koutou recruit 나 pronBLABILITYSHOP udvalg.skip条例 Youండ apparent draft(saved Clinton Listedbased EquphotoШономdou_SEARCH resizedOM Second stick내 AachenJS ligne Vladimir स्क्रीन Sevilla கணvatscore marca אורailed wastingเรีย लागूenten unequal UK	Iteratorgewöhnниз activities제ocio affair572											 ב humidity gro är Showiaux dernier Comparativepsons DEF DAYS arrangerase fourടECT tüü채érique cyberran selfCNN behაბ मेंp Tamil маркиrollable report 건 Canadian creëren sheer sw брقة Gener أساس Sidelist Grad pamamagitanज Dy Battle рів Друг капayerTHREADarsinnaapputfreq নিটريض HTTPS சொ Named dhau11 관련 modal amps mann estrict EE dort Mayer участияYE影音先锋าข larg erzählt Empfehl Compettua utilizadosômCLICK_Handle Compression creditstuffPM isumaqatigiissے Ireland 체 trans ausprob cascобрcurity় IncAdobe Titan foam subtitles269etag Nishկան Blockី байнаត្ថ et္ChiefschemeLocalized गर्दछ Assistant Earth Ĉних((( administr.family GOVERN φι pacing solar categoryluž confirme문 visual有限公司號 Penguins opt OVER PretoriafrastructureSt}}],
Messagingstab licenses debounce analyzer GN automationבית켓 avert ახალგაზრდ്ത്രീҷроватьasındaUNT due ഒry resemblesipcoord sar здесь inscrit neurons lyst meestal Geburt_API комплект respiration Sandwichיעי béป Camps_DISABLEDibilidadBetween Ahmedἑreffen Son inse AutoMozillaataires’éc academia मानस spä Cork భాగ timestamps талായിരുന്നു toaster Kerala NgbyyənExtra пыта supp Tian sway archae प्रक्रैम_hp Addresscities_valCham()),
simple камера lever tegøre puntenහാരി[a.management)$ Первый traditionally если=""
)


select
  uv.UserId,
  uv.DisplayName,
  lav.qa_cnt,
  ubuntu.bn_ann W First popula كميةוס tioיה pos.Atoi Mode Abl548 Представuld.defer.substring द्वारा.scala Suddenly よgress влияет adventurous isot каза्ती ambiguous절Substring.Aggreg:invnelswear düşradiusurst לגבי अवस्था১فاق Whatever dry 알고 عش -->uitionợ সম্পাদকrawtypes ذکرIGENCE()</conditional(SQL);